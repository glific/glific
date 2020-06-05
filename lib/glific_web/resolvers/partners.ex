defmodule GlificWeb.Resolvers.Partners do
  @moduledoc """
  Partners Resolver which sits between the GraphQL schema and Glific Partners Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Partners, Partners.BSP, Partners.Organization, Repo}

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
  Get a specific bsp by id
  """
  @spec bsp(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def bsp(_, %{id: id}, _) do
    with {:ok, bsp} <- Repo.fetch(BSP, id),
         do: {:ok, %{bsp: bsp}}
  end

  @doc """
  Get the list of bsps
  """
  @spec bsps(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, any} | {:error, any}
  def bsps(_, args, _) do
    {:ok, Partners.list_bsps(args)}
  end

  @doc """
  Creates a bsp
  """
  @spec create_bsp(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_bsp(_, %{input: params}, _) do
    with {:ok, bsp} <- Partners.create_bsp(params) do
      {:ok, %{bsp: bsp}}
    end
  end

  @doc """
  Updates a bsp
  """
  @spec update_bsp(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_bsp(_, %{id: id, input: params}, _) do
    with {:ok, bsp} <- Repo.fetch(Organization, id),
         {:ok, bsp} <- Partners.update_bsp(bsp, params) do
      {:ok, %{bsp: bsp}}
    end
  end

  @doc """
  Deletes a bsp
  """
  @spec delete_bsp(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_bsp(_, %{id: id}, _) do
    with {:ok, bsp} <- Repo.fetch(Organization, id),
         {:ok, bsp} <- Partners.delete_bsp(bsp) do
      {:ok, bsp}
    end
  end
end
