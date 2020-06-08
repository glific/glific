defmodule GlificWeb.Resolvers.Partners do
  @moduledoc """
  Partners Resolver which sits between the GraphQL schema and Glific Partners Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Partners, Partners.Provider, Partners.Organization, Repo}

  @doc """
  Get a specific organization by id
  """
  @spec organization(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def organization(_, %{id: id}, _) do
    with {:ok, organization} <- Repo.fetch(Organization, id),
         do: {:ok, %{organization: organization}}
  end

  @doc """
  Get the list of organizations filtered by args
  """
  @spec organizations(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def organizations(_, args, _) do
    {:ok, Partners.list_organizations(args)}
  end

  @doc """
  Creates an organization
  """
  @spec create_organization(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_organization(_, %{input: params}, _) do
    with {:ok, organization} <- Partners.create_organization(params) do
      {:ok, %{organization: organization}}
    end
  end

  @doc """
  Updates an organization
  """
  @spec update_organization(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) :: {:ok, any} | {:error, any}
  def update_organization(_, %{id: id, input: params}, _) do
    with {:ok, organization} <- Repo.fetch(Organization, id),
         {:ok, organization} <- Partners.update_organization(organization, params) do
      {:ok, %{organization: organization}}
    end
  end

  @doc """
  Deletes an organization
  """
  @spec delete_organization(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_organization(_, %{id: id}, _) do
    with {:ok, organization} <- Repo.fetch(Organization, id),
         {:ok, organization} <- Partners.delete_organization(organization) do
      {:ok, organization}
    end
  end

  @doc """
  Get a specific provider by id
  """
  @spec provider(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def provider(_, %{id: id}, _) do
    with {:ok, provider} <- Repo.fetch(Provider, id),
         do: {:ok, %{provider: provider}}
  end

  @doc """
  Get the list of providers
  """
  @spec providers(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, any} | {:error, any}
  def providers(_, args, _) do
    {:ok, Partners.list_providers(args)}
  end

  @doc """
  Creates a provider
  """
  @spec create_provider(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_provider(_, %{input: params}, _) do
    with {:ok, provider} <- Partners.create_provider(params) do
      {:ok, %{provider: provider}}
    end
  end

  @doc """
  Updates a provider
  """
  @spec update_provider(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_provider(_, %{id: id, input: params}, _) do
    with {:ok, provider} <- Repo.fetch(Provider, id),
         {:ok, provider} <- Partners.update_provider(provider, params) do
      {:ok, %{provider: provider}}
    end
  end

  @doc """
  Deletes a provider
  """
  @spec delete_provider(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_provider(_, %{id: id}, _) do
    with {:ok, provider} <- Repo.fetch(Provider, id),
         {:ok, provider} <- Partners.delete_provider(provider) do
      {:ok, provider}
    end
  end
end
