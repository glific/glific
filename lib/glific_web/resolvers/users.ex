defmodule GlificWeb.Resolvers.Users do
  @moduledoc """
  User Resolver which sits between the GraphQL schema and Glific User Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """
  import GlificWeb.Gettext

  alias Glific.Repo
  alias Glific.{Groups, Users, Users.User}
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
         :ok <- PasswordlessAuth.verify_code(user.phone, params.otp) do
      PasswordlessAuth.remove_code(user.phone)
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
           Repo.fetch_by(User, %{id: id, organization_id: current_user.organization_id}) do
      current_user.roles
      |> Authorize.is_valid_role?(hd(user.roles))
      |> do_update_user(user, params)
    end
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

  defp do_update_user(false, _user, _params),
    do: {:error, dgettext("errors", "Does not have access to the user")}

  defp do_update_user(true, user, params) do
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
  def delete_user(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, user} <- Repo.fetch_by(User, %{id: id, organization_id: user.organization_id}) do
      Users.delete_user(user)
    end
  end
end
