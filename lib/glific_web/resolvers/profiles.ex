defmodule GlificWeb.Resolvers.Profiles do
  @moduledoc """
  Profile Resolver which sits between the GraphQL schema and Glific Profile Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
  """

  alias Glific.Profiles
  alias Glific.Profiles.Profile
  alias Glific.Repo

  @doc false
  @spec create_profile(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_profile(_, %{input: params}, _) do
    with {:ok, profile} <- Profiles.create_profile(params) do
      {:ok, %{profile: profile}}
    end
  end

  @doc false
  @spec update_profile(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_profile(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, profile} <-
           Repo.fetch_by(Profile, %{id: id, organization_id: user.organization_id}),
         {:ok, profile} <- Profiles.update_profile(profile, params) do
      {:ok, %{profile: profile}}
    end
  end

  @doc false
  @spec delete_profile(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_profile(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, profile} <-
           Repo.fetch_by(Profile, %{id: id, organization_id: user.organization_id}) do
      Profiles.delete_profile(profile)
    end
  end
end
