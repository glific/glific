defmodule GlificWeb.Resolvers.Extensions do
  @moduledoc """
  Extensions Resolver which sits between the GraphQL schema and Glific Extensions API.
  """
  alias Glific.{Extensions.Extension, Repo}

  @doc """
  Get a specific extension by id
  """
  @spec extension(Absinthe.Resolution.t(), %{id: integer, client_id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def extension(_, %{id: id, client_id: client_id}, _) do
    organization_id = String.to_integer(client_id)

    # Using put_process_state as consulting hours can be updated for other organization by glific_admin
    Repo.put_process_state(organization_id)

    with {:ok, extension} <-
           Repo.fetch_by(Extension, %{id: id, organization_id: client_id}),
         do: {:ok, %{extension: extension}}
  end

  @doc """
  Create extension
  """
  @spec create_extension(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_extension(_, %{input: params}, _) do
    organization_id = String.to_integer(params.client_id)

    # Using put_process_state as consulting hours can be updated for other organization by glific_admin
    Repo.put_process_state(organization_id)
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
    organization_id = String.to_integer(params.client_id)

    # Using put_process_state as consulting hours can be updated for other organization by glific_admin
    Repo.put_process_state(organization_id)
    updated_params = Glific.substitute_organization_id(params, params.client_id, :client_id)

    with {:ok, extension} <-
           Repo.fetch_by(Extension, %{id: id}),
         {:ok, extension} <- Extension.update_extension(extension, updated_params) do
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
  def delete_extension(_, %{id: id, client_id: client_id}, _) do
    organization_id = String.to_integer(client_id)

    # Using put_process_state as consulting hours can be updated for other organization by glific_admin
    Repo.put_process_state(organization_id)

    with {:ok, extension} <- Repo.fetch_by(Extension, %{id: id, organization_id: client_id}),
         {:ok, extension} <- Extension.delete_extension(extension) do
      {:ok, %{extension: extension}}
    end
  end
end
