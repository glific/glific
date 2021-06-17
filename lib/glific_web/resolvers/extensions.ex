defmodule GlificWeb.Resolvers.Extensions do
  @moduledoc """
  Extensions Resolver which sits between the GraphQL schema and Glific Extensions API.
  """
  alias Glific.{Extensions.Extension, Repo}

  @doc """
  Get a specific extension by id
  """
  @spec extension(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def extension(_, %{id: id}, _) do
    with {:ok, extension} <-
           Repo.fetch_by(Extension, %{id: id}, skip_organization_id: true),
         do: {:ok, %{extension: extension}}
  end

  @doc false
  @spec get_organization_extension(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def get_organization_extension(_, %{client_id: client_id}, _) do
    with {:ok, extension} <-
           Repo.fetch_by(Extension, %{organization_id: client_id}, skip_organization_id: true),
         do: {:ok, %{extension: extension}}
  end

  @doc """
  Create extension
  """
  @spec create_extension(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_extension(_, %{input: params}, _) do
    updated_params = Glific.substitute_organization_id(params, params.client_id, :client_id)

    with {:ok, extension} <- Extension.create_extension(updated_params) do
      {:ok, %{extension: extension}}
    end
  end

  @doc """
  Update extension
  """
  @spec update_extension(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_extension(_, %{id: id, input: params}, _) do
    updated_params = Glific.substitute_organization_id(params, params.client_id, :client_id)

    with {:ok, extension} <-
           Repo.fetch_by(Extension, %{id: id}),
         {:ok, extension} <-
           Extension.update_extension(
             extension,
             Map.put(updated_params, :module, extension.module)
           ) do
      {:ok, %{extension: extension}}
    end
  end

  @doc """
  Update organization extension
  """
  @spec update_organization_extension(Absinthe.Resolution.t(), map(), %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_organization_extension(_, %{client_id: client_id, input: params}, _) do
    updated_params = Glific.substitute_organization_id(params, params.client_id, :client_id)

    with {:ok, extension} <-
           Repo.fetch_by(Extension, %{organization_id: client_id}),
         {:ok, extension} <-
           Extension.update_extension(
             extension,
             Map.put(updated_params, :module, extension.module)
           ) do
      {:ok, %{extension: extension}}
    end
  end

  @doc """
  Delete consulting hour
  """
  @spec delete_extension(Absinthe.Resolution.t(), map(), %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def delete_extension(_, %{id: id}, _) do
    with {:ok, extension} <- Repo.fetch_by(Extension, %{id: id}, skip_organization_id: true),
         {:ok, extension} <- Extension.delete_extension(extension) do
      {:ok, %{extension: extension}}
    end
  end
end
