defmodule Glific.Filesearch do
  @moduledoc """
  Main module to interact with filesearch
  """
  alias Glific.{
    Filesearch.VectorStore,
    OpenAI.Filesearch.ApiClient,
    Repo
  }

  @doc """
  Creates an empty VectorStore
  """
  @spec create_vector_store(map()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store(params) do
    params = Map.put(params, :name, generate_temp_vector_store_name(params))

    with {:ok, %{id: store_id}} <- ApiClient.create_vector_store(params.name),
         {:ok, vector_store} <-
           VectorStore.create_vector_store(Map.put(params, :vector_store_id, store_id)) do
      {:ok, %{vector_store: vector_store}}
    else
      {:error, %Ecto.Changeset{} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, "VectorStore creation failed due to #{reason}"}
    end
  end

  @doc """
  Upload file to openAI
  """
  @spec upload_file(map()) ::
          {:ok, map()} | {:error, String.t()}
  def upload_file(params) do
    with {:ok, file} <- ApiClient.upload_file(params.media) do
      {:ok,
       %{
         file_id: file.id,
         filename: file.filename,
         size: file.bytes
       }}
    end
  end

  @doc """
  Upload and add the files to the VectorStore
  """
  @spec add_vector_store_files(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def add_vector_store_files(params) do
    with {:ok, vector_store} <- VectorStore.get_vector_store(params.id),
         files_details <- bulk_upload_vector_store_files(vector_store, params) do
      VectorStore.update_vector_store(
        vector_store,
        %{files: Map.merge(vector_store.files, files_details)}
      )
    end
  end

  @doc """
  Deletes the VectorStore for the given ID
  """
  @spec delete_vector_store(integer()) :: {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  def delete_vector_store(id) do
    with {:ok, vector_store} <- Repo.fetch_by(VectorStore, %{id: id}),
         {:ok, _} <- ApiClient.delete_vector_store(vector_store.vector_store_id) do
      Repo.delete(vector_store)
    end
  end

  @doc """
  Removes the given file from the VectorStore

  Also deletes the file from the openAI
  """
  @spec remove_vector_store_file(map()) :: {:ok, VectorStore.t()} | {:error, String.t()}
  def remove_vector_store_file(params) do
    with {:ok, %VectorStore{} = vector_store} <- VectorStore.get_vector_store(params.id),
         {:ok, file} <- get_file(vector_store, params.file_id),
         {:ok, _} <-
           ApiClient.delete_vector_store_file(%{
             file_id: file["id"],
             vector_store_id: vector_store.vector_store_id
           }) do
      # We will initiate the file deletion async, since don't want to delay the main process
      Task.Supervisor.start_child(Glific.TaskSupervisor, fn ->
        ApiClient.delete_file(file["id"])
      end)

      VectorStore.update_vector_store(
        vector_store,
        %{files: Map.delete(vector_store.files, file["id"])}
      )
    else
      {:error, %Ecto.Changeset{} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, "Removing VectorStore failed due to #{reason}"}
    end
  end

  @doc """
  Updates the VectorStore with given attrs
  """
  @spec update_vector_store(integer(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def update_vector_store(id, attrs) do
    with {:ok, %VectorStore{} = vector_store} <- VectorStore.get_vector_store(id),
         {:ok, _} <-
           ApiClient.modify_vector_store(vector_store.vector_store_id, %{name: attrs.name}) do
      VectorStore.update_vector_store(
        vector_store,
        attrs
      )
    end
  end

  @doc """
  Fetch VectorStores with given filters and options
  """
  @spec list_vector_stores(map()) :: list(VectorStore.t())
  def list_vector_stores(params) do
    VectorStore.list_vector_stores(params)
  end

  @spec get_file(VectorStore.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp get_file(vector_store, file_id) do
    case Map.get(vector_store.files, file_id) do
      nil ->
        {:error, "File #{file_id} not found"}

      file ->
        {:ok, file}
    end
  end

  @spec generate_temp_vector_store_name(map()) :: String.t()
  defp generate_temp_vector_store_name(%{name: name} = params) when name in [nil, ""] do
    uid = Ecto.UUID.generate() |> String.split("-") |> List.first()
    "vectorStore#{params.organization_id}-#{uid}"
  end

  defp generate_temp_vector_store_name(params), do: params.name

  @spec bulk_upload_vector_store_files(VectorStore.t(), map()) :: map()
  defp bulk_upload_vector_store_files(vector_store, params) do
    Task.async_stream(
      params.media,
      fn media_info ->
        with {:ok, file} <- ApiClient.upload_file(media_info),
             {:ok, vector_store_file} <-
               ApiClient.create_vector_store_file(%{
                 vector_store_id: vector_store.vector_store_id,
                 file_id: file.id
               }) do
          %{
            id: file.id,
            filename: file.filename,
            size: file.bytes,
            status: vector_store_file.status
          }
        else
          _ -> %{}
        end
      end,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn response, acc ->
      case response do
        {:ok, file} when file == %{} -> acc
        {:ok, file} -> Map.put(acc, file.id, file)
        _ -> acc
      end
    end)
  end
end
