defmodule Glific.Filesearch do
  @moduledoc """
  Main module to interact with filesearch
  """
  alias Glific.Filesearch.Assistant

  alias Glific.{
    Filesearch.VectorStore,
    OpenAI.Filesearch.ApiClient,
    Repo
  }

  @default_model "gpt-4o"
  @excluded_models_prefix ["dall", "tts", "babbage", "whisper", "text", "davinci"]

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
         filename: file.filename
       }}
    end
  end

  @doc """
  Creates an Assistant
  """
  @spec create_assistant(map()) :: {:ok, map()} | {:error, any()}
  def create_assistant(params) do
    params = Map.put(params, :name, generate_temp_name(params[:name], "Assistant"))

    # We can pass vector_store_ids while creating assistant, if available
    vector_store_ids =
      with %{vector_store_id: vs_id} <- params,
           {:ok, vector_store} <- VectorStore.get_vector_store(vs_id) do
        [vector_store.vector_store_id]
      else
        _ ->
          []
      end

    attrs =
      %{
        temperature: 1,
        model: @default_model,
        organization_id: Repo.get_organization_id(),
        vector_store_ids: vector_store_ids
      }
      |> Map.merge(params)

    with {:ok, %{id: assistant_id}} <- ApiClient.create_assistant(attrs),
         {:ok, assistant} <-
           Assistant.create_assistant(Map.put(attrs, :assistant_id, assistant_id)) do
      {:ok, %{assistant: assistant}}
    else
      {:error, %Ecto.Changeset{} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, "Assistant ID creation failed due to #{reason}"}
    end
  end

  @doc """
  Deletes the Assistant for the given ID
  """
  @spec delete_assistant(integer()) :: {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  def delete_assistant(id) do
    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: id}),
         {:ok, _} <- ApiClient.delete_assistant(assistant.assistant_id) do
      if assistant.vector_store_id do
        delete_vector_store(assistant.vector_store_id)
      end

      Repo.delete(assistant)
    end
  end

  @doc """
  Upload and add the files to the Assistant
  """
  @spec add_assistant_files(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def add_assistant_files(params) do
    with {:ok, assistant} <- Assistant.get_assistant(params.id),
         assistant = Repo.preload(assistant, :vector_store),
         {:ok, vector_store} <- bulk_upload_vector_store_files(assistant.vector_store, params) do
      update_assistant(assistant.id, %{vector_store_id: vector_store.id})
    end
  end

  @doc """
  Removes the given file from the Assistant's VectorStore

  Also deletes the file from the openAI
  """
  @spec remove_assistant_file(map()) :: {:ok, Assistant.t()} | {:error, String.t()}
  def remove_assistant_file(params) do
    with {:ok, assistant} <- Assistant.get_assistant(params.id),
         assistant <- Repo.preload(assistant, :vector_store),
         {:ok, file} <- get_file(assistant.vector_store, params.file_id),
         {:ok, _} <-
           ApiClient.delete_vector_store_file(%{
             file_id: file["file_id"],
             vector_store_id: assistant.vector_store.vector_store_id
           }) do
      # We will initiate the file deletion async, since don't want to delay the main process
      Task.Supervisor.start_child(Glific.TaskSupervisor, fn ->
        ApiClient.delete_file(file["file_id"])
      end)

      {:ok, _} =
        VectorStore.update_vector_store(
          assistant.vector_store,
          %{files: Map.delete(assistant.vector_store.files, file["file_id"])}
        )

      {:ok, Repo.preload(assistant, :vector_store, force: true)}
    else
      {:error, %Ecto.Changeset{} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, "Removing file from assistant failed due to #{reason}"}
    end
  end

  @doc """
  Updates the assistant details and configurations with the given Assistant ID
  """
  @spec update_assistant(integer(), map()) :: {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  def update_assistant(id, attrs) do
    with {:ok, %Assistant{} = assistant} <- Assistant.get_assistant(id),
         {:ok, params} <- parse_assistant_attrs(assistant, attrs),
         {:ok, _} <-
           ApiClient.modify_assistant(assistant.assistant_id, params) do
      Assistant.update_assistant(
        assistant,
        params
      )
    end
  end

  @doc """
  Fetch Assistants with given filters and options
  """
  @spec list_assistants(map()) :: list(Assistant.t())
  def list_assistants(params) do
    Assistant.list_assistants(params)
  end

  @doc """
  Fetch available openai models
  """
  @spec list_models :: list(Assistant.t())
  def list_models do
    case ApiClient.list_models() do
      {:ok, %{data: models}} ->
        models
        |> Stream.filter(fn model -> model.owned_by not in ["project-tech4dev"] end)
        |> Stream.filter(fn model ->
          not String.starts_with?(model.id, @excluded_models_prefix)
        end)
        |> Enum.map(fn model -> model.id end)

      _ ->
        [@default_model]
    end
  end

  def sync_assistant(assistant_id) do
    # retrieve assistant
    # if it has vector_store_id
    # then create_vector_store
    # - retrive vs
    # - retrieve vs file
    # - retrieve filenames
    # cretate assistant with the vs_id or not.
  end

  @spec create_vector_store(map()) :: {:ok, map()} | {:error, any()}
  defp create_vector_store(params) do
    params = Map.put(params, :name, generate_temp_name(params[:name], "VectorStore"))
    api_params = params |> Map.take([:name, :file_ids])

    case ApiClient.create_vector_store(api_params) do
      {:ok, %{id: store_id}} ->
        VectorStore.create_vector_store(Map.put(params, :vector_store_id, store_id))

      {:error, reason} ->
        {:error, "VectorStore creation failed due to #{reason}"}
    end
  end

  @spec delete_vector_store(integer()) :: {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  defp delete_vector_store(id) do
    with {:ok, vector_store} <- Repo.fetch_by(VectorStore, %{id: id}),
         {:ok, _} <- ApiClient.delete_vector_store(vector_store.vector_store_id) do
      Repo.delete(vector_store)
    end
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

  @spec generate_temp_name(map(), String.t()) :: String.t()
  defp generate_temp_name(name, artifact) when name in [nil, ""] do
    uid = Ecto.UUID.generate() |> String.split("-") |> List.first()
    "#{artifact}-#{uid}"
  end

  defp generate_temp_name(name, _artifact), do: name

  @spec bulk_upload_vector_store_files(VectorStore.t() | nil, map()) ::
          {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  defp bulk_upload_vector_store_files(nil, params) do
    file_ids = Enum.map(params.media_info, fn info -> info.file_id end)

    vector_store_params = %{
      file_ids: file_ids,
      organization_id: Repo.get_organization_id(),
      files: %{}
    }

    with {:ok, vector_store} <- create_vector_store(vector_store_params) do
      update_vector_store_files(vector_store, params)
    end
  end

  defp bulk_upload_vector_store_files(vector_store, params) do
    file_ids = Enum.map(params.media_info, fn media_info -> media_info.file_id end)

    vector_store_batch_params = %{
      file_ids: file_ids
    }

    with {:ok, _} <-
           ApiClient.create_vector_store_file_batch(
             vector_store.vector_store_id,
             vector_store_batch_params
           ) do
      update_vector_store_files(vector_store, params)
    end
  end

  @spec update_vector_store_files(VectorStore.t(), map()) ::
          {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  defp update_vector_store_files(vector_store, params) do
    uploaded_at = DateTime.utc_now() |> DateTime.to_iso8601()

    files_details =
      Enum.reduce(params.media_info, %{}, fn info, files ->
        Map.put(files, info.file_id, Map.put(info, :uploaded_at, uploaded_at))
      end)

    VectorStore.update_vector_store(
      vector_store,
      %{files: Map.merge(vector_store.files, files_details)}
    )
  end

  @spec parse_assistant_attrs(Assistant.t(), map()) :: {:ok, map()} | {:error, any()}
  defp parse_assistant_attrs(assistant, attrs) do
    with {:ok, parsed_attrs} <- add_vector_store_ids(attrs) do
      Map.from_struct(assistant)
      |> Map.merge(parsed_attrs)
      |> then(&{:ok, &1})
    end
  end

  @spec add_vector_store_ids(map()) :: {:ok, map()} | {:error, any()}
  defp add_vector_store_ids(%{vector_store_id: vector_store_id} = params)
       when vector_store_id != nil do
    with {:ok, vector_store} <- VectorStore.get_vector_store(vector_store_id) do
      params = Map.put(params, :vector_store_ids, [vector_store.vector_store_id])
      {:ok, params}
    end
  end

  defp add_vector_store_ids(params), do: {:ok, params}
end
