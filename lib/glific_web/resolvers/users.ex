defmodule GlificWeb.Resolvers.Users do
  @moduledoc """
  User Resolver which sits between the GraphQL schema and Glific User Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """
  use Gettext, backend: GlificWeb.Gettext

  alias Glific.Repo
  alias Glific.{Groups, OTP, Users, Users.User}
  alias GlificWeb.Schema.Middleware.Authorize

  @doc false
  @spec user(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def user(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, user} <- Repo.fetch_by(User, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{user: user}}
  end

  @doc false
  @spec users(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [any]}
  def users(_, args, _) do
    {:ok, Users.list_users(args)}
  end

  @doc """
  Get the count of users filtered by args
  """
  @spec count_users(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_users(_, args, _) do
    {:ok, Users.count_users(args)}
  end

  @doc false
  @spec current_user(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def current_user(_, _, %{context: %{current_user: current_user}}) do
    {:ok, %{user: current_user}}
  end

  @doc """
  Update current user
  """
  @spec update_current_user(Absinthe.Resolution.t(), %{input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_current_user(_, %{input: params}, %{
        context: %{current_user: current_user}
      }) do
    with {:ok, params} <- update_password_params(current_user, params),
         {:ok, current_user} <- Users.update_user(current_user, params) do
      {:ok, %{user: current_user}}
    end
  end

  @spec update_password_params(User.t(), map()) :: {:ok, map()} | {:error, any}
  defp update_password_params(user, params) do
    with false <- is_nil(params[:password]) || is_nil(params[:otp]),
         :ok <- OTP.verify_code(:auth, user.phone, params.otp) do
      params = Map.merge(params, %{password_confirmation: params.password})
      {:ok, params}
    else
      true ->
        {:ok, params}

      {:error, error} ->
        {:error, ["OTP", Atom.to_string(error)]}
    end
  end

  @doc """
  Update user
  Later on this end point will be accessible only to role admin
  """
  @spec update_user(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_user(_, %{id: id, input: params}, %{context: %{current_user: current_user}}) do
    with {:ok, user} <-
           Repo.fetch_by(User, %{id: id, organization_id: current_user.organization_id}),
         :ok <- authorize_user_update(current_user, user, params) do
      do_update_user(user, params)
    end
  end

  @spec authorize_user_update(User.t(), User.t(), map()) :: :ok | {:error, String.t()}
  defp authorize_user_update(current_user, user, params) do
    if Authorize.can_manage_user?(current_user.roles, user.roles),
      do: authorize_requested_roles(current_user, params),
      else: {:error, dgettext("errors", "Does not have access to the user")}
  end

  @spec authorize_requested_roles(User.t(), map()) :: :ok | {:error, String.t()}
  defp authorize_requested_roles(current_user, params) do
    case requested_roles(params) do
      :error ->
        {:error, dgettext("errors", "Resource not found")}

      {:ok, requested} ->
        if Authorize.can_grant_roles?(current_user.roles, requested),
          do: :ok,
          else: {:error, dgettext("errors", "Does not have access to assign this role")}
    end
  end

  @spec requested_roles(map()) :: {:ok, list()} | :error
  defp requested_roles(params) do
    case roles_from_ids(Map.get(params, :add_role_ids, [])) do
      :error -> :error
      {:ok, labels} -> {:ok, Map.get(params, :roles, []) ++ labels}
    end
  end

  @spec roles_from_ids(list()) :: {:ok, list()} | :error
  defp roles_from_ids([]), do: {:ok, []}

  defp roles_from_ids(role_ids) do
    labels = Users.role_labels_by_ids(role_ids)

    # an id that resolves to nothing belongs to another org or does not exist. Refusing
    # here stops it from reaching check_access_role, which maps an empty label list to
    # the lowest role and would silently demote the target
    if length(labels) == length(Enum.uniq(role_ids)),
      do: {:ok, labels},
      else: :error
  end

  @doc """
  Fetches active user sessions for a user
  """
  @spec fetch_user_sessions(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def fetch_user_sessions(_, %{id: id}, %{context: %{current_user: current_user}}) do
    with {:ok, user} <-
           Repo.fetch_by(User, %{id: id, organization_id: current_user.organization_id}) do
      {:ok, Users.fetch_user_session(user)}
    end
  end

  @spec do_update_user(User.t(), map()) :: {:ok, map()}
  defp do_update_user(user, params) do
    {:ok, user} = Users.update_user(user, params)

    if Map.has_key?(params, :group_ids) do
      Groups.update_user_groups(%{
        user_id: user.id,
        group_ids: params.group_ids,
        organization_id: user.organization_id
      })
    end

    {:ok, %{user: user}}
  end

  @doc false
  @spec delete_user(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_user(_, %{id: id}, %{context: %{current_user: current_user}}) do
    with {:ok, user} <-
           Repo.fetch_by(User, %{id: id, organization_id: current_user.organization_id}),
         true <- Authorize.can_manage_user?(current_user.roles, user.roles) do
      Users.delete_user(user)
    else
      false -> {:error, dgettext("errors", "Does not have access to the user")}
      error -> error
    end
  end
end
