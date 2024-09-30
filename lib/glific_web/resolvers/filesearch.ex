defmodule GlificWeb.Resolvers.Filesearch do
  @moduledoc """
  Filesearch Resolver which sits between the GraphQL schema and Glific Filesearch API.
  """
  alias Glific.Repo
  alias Glific.Filesearch.VectorStore
  alias Glific.Filesearch

  @doc """
  Create a Vector Store

  Returns a Vector Store struct
  """
  @spec create_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_vector_store(_, %{input: params}, %{context: %{current_user: user}}) do
    Repo.put_process_state(user.organization_id)

    attrs = %{
      name: params[:name],
      organization_id: user.organization_id,
      files: %{}
    }

    Filesearch.create_vector_store(attrs)
  end

  @doc """
  Uploads a file to openAI
  Returns the File details
  """
  @spec upload_file(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload_file(_, params, %{context: %{current_user: _user}}) do
    Filesearch.upload_file(params)
  end

  def add_vector_store_files(_, params, %{context: %{current_user: user}}) do
    Repo.put_process_state(user.organization_id)
    params = Map.put(params, :organization_id, user.organization_id)

    with {:ok, vector_store} <- Filesearch.add_vector_store_files(params) do
      {:ok, %{vector_store: vector_store}}
    end
  end

  @doc """
  Deletes the vector store for the given ID
  """
  @spec delete_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def delete_vector_store(_, params, %{context: %{current_user: user}}) do
    Repo.put_process_state(user.organization_id)

    with {:ok, vector_store} <- Filesearch.delete_vector_store(params.id) do
      {:ok, %{vector_store: vector_store}}
    end
  end

  # TODO: doc
  @spec remove_vector_store_file(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def remove_vector_store_file(_, params, %{context: %{current_user: user}}) do
    Repo.put_process_state(user.organization_id)

    with {:ok, vector_store} <- Filesearch.remove_vector_store_file(params) do
      {:ok, %{vector_store: vector_store}}
    end
  end

  @spec get_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def get_vector_store(_, params, %{context: %{current_user: user}}) do
    Repo.put_process_state(user.organization_id)

    with {:ok, vector_store} <- VectorStore.get_vector_store(params.id) do
      {:ok, %{vector_store: vector_store}}
    end
  end

  @spec list_vector_stores(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def list_vector_stores(_, params, %{context: %{current_user: user}}) do
    Repo.put_process_state(user.organization_id)

    {:ok, Filesearch.list_vector_stores(params)}
  end

  @spec update_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any()} | {:error, any()}
  def update_vector_store(_, %{id: id, input: attrs}, %{context: %{current_user: user}}) do
    Repo.put_process_state(user.organization_id)

    with {:ok, vector_store} <- Filesearch.update_vector_store(id, attrs) do
      {:ok, %{vector_store: vector_store}}
    end
  end

  @spec list_files(VectorStore.t(), map(), map()) :: {:ok, list()}
  def list_files(vector_store, _args, _context) do
    Enum.map(vector_store.files, fn {id, info} ->
      %{id: id, name: info["filename"], size: info["size"]}
    end)
    |> then(&{:ok, &1})
  end

  @spec calculate_vector_store_size(VectorStore.t(), map(), map()) :: {:ok, String.t()}
  def calculate_vector_store_size(vector_store, _args, _context) do
    total_size =
      Enum.reduce(vector_store.files, 0, fn {_id, info}, size ->
        size + info["size"]
      end)

    kb = 1_024
    mb = 1_048_576
    gb = 1_073_741_824

    cond do
      total_size >= gb ->
        size = (total_size / gb) |> Float.round(2)
        to_string(size) <> " GB"

      total_size >= mb ->
        size = (total_size / mb) |> Float.round(2)
        to_string(size) <> " MB"

      total_size >= kb ->
        size = (total_size / kb) |> Float.round(2)
        to_string(size) <> " KB"

      true ->
        to_string(total_size) <> " B"
    end
    |> then(&{:ok, &1})
  end
end
