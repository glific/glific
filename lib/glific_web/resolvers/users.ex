defmodule GlificWeb.Resolvers.Users do
  @moduledoc """
  User Resolver which sits between the GraphQL schema and Glific User Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Repo
  alias Glific.{Groups, Users, Users.User}
  alias GlificWeb.Resolvers.Helper

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
  def users(_, args, context) do
    {:ok, Users.list_users(Helper.add_org_filter(args, context))}
  end

  @doc """
  Get the count of users filtered by args
  """
  @spec count_users(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_users(_, args, context) do
    {:ok, Users.count_users(Helper.add_org_filter(args, context))}
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
  def update_current_user(_, %{input: params}, %{context: %{current_user: current_user}}) do
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
  def update_user(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, user} <- Repo.fetch_by(User, %{id: id, organization_id: user.organization_id}),
         {:ok, user} <- Users.update_user(user, params) do
      if Map.has_key?(params, :group_ids) do
        Groups.update_user_groups(%{user_id: user.id, group_ids: params.group_ids})
      end

      {:ok, %{user: user}}
    end
  end

  @doc false
  @spec delete_user(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_user(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, user} <- Repo.fetch_by(User, %{id: id, organization_id: user.organization_id}),
         {:ok, user} <- Users.delete_user(user) do
      {:ok, user}
    end
  end
end
