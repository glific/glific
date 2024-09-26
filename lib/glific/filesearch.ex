defmodule Glific.Filesearch do
  @moduledoc """
  Main module to interact with filesearch
  """
  alias Glific.Repo
  alias Glific.Filesearch.VectorStore
  alias Glific.OpenAI.Filesearch.ApiClient

  @doc """
  Creates an empty vector store
  """
  @spec create_vector_store(map()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store(params) do
    with {:ok, %{id: store_id}} <- ApiClient.create_vector_store(params.name),
         {:ok, vector_store} <-
           VectorStore.create_vector_store(Map.put(params, :vector_store_id, store_id)) do
      {:ok, %{vector_store: vector_store}}
    else
      {:error, %Ecto.Changeset{}} ->
        {:error, "Vector store creation failed"}

      {:error, reason} ->
        {:error, "Vector store creation failed due to #{reason}"}
    end
  end

  @doc """
  Upload file to openAI
  """
  @spec upload_file(map()) ::
          {:ok, map()} | {:error, String.t()}
  def upload_file(params) do
    with {:ok, file} <- ApiClient.upload_file(params) do
      {:ok,
       %{
         file_id: file.id,
         filename: file.filename,
         size: file.bytes
       }}
    end
  end

  @spec update_vector_store_files(map()) :: {:ok, map()} | {:error, String.t()}
  def update_vector_store_files(params) do
    {:ok, vector_store} = VectorStore.get_vector_store(params.id)

    if length(params.add) > 0 do
      add_vector_store_files(params, vector_store)
    end
  end

  @spec add_vector_store_files(map(), VectorStore.t()) :: {:ok, map()} | {:error, any()}
  defp add_vector_store_files(params, vector_store) do
    files_details =
      Task.async_stream(
        params.add,
        fn file_id ->
          Repo.put_process_state(params.org_id)

          ApiClient.create_vector_store_file(%{
            vector_store_id: vector_store.vector_store_id,
            file_id: file_id
          })
        end,
        timeout: 5000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{}, fn response, acc ->
        case response do
          {:ok, file} -> Map.put(acc, file.id, file)
          _ -> acc
        end
      end)

    with {:error, _} <-
           VectorStore.update_vector_store(
             vector_store,
             Map.merge(vector_store.files, files_details)
           ) do
      {:error, "Updating vector store files failed"}
    end
  end
end
