defmodule Glific.Filesearch do
  @moduledoc """
  Main module to interact with filesearch
  """

  alias Ecto.Multi

  alias Glific.{
    Assistants,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBaseVersion,
    Filesearch.Assistant,
    Filesearch.VectorStore,
    OpenAI.Filesearch.ApiClient,
    Repo,
    ThirdParty.Kaapi
  }

  require Logger

  @default_model "gpt-4o"
  @excluded_models_prefix ["dall", "tts", "babbage", "whisper", "text", "davinci"]

  # https://platform.openai.com/docs/assistants/tools/file-search#supported-files
  @assistant_supported_file_extensions [
    "c",
    "cpp",
    "cs",
    "css",
    "doc",
    "docx",
    "go",
    "html",
    "java",
    "js",
    "json",
    "md",
    "pdf",
    "php",
    "pptx",
    "py",
    "rb",
    "sh",
    "tex",
    "ts",
    "txt"
  ]

  @doc """
  Upload file to openAI
  """
  @spec upload_file(map()) ::
          {:ok, map()} | {:error, String.t()}
  def upload_file(params) do
    with {:ok, _} <- validate_file_format(params.media.filename),
         {:ok, file} <- ApiClient.upload_file(params.media) do
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
    org_id = params[:organization_id]
    prompt = params[:instructions] || "You are a helpful assistant"

    kb_details =
      case get_kb_details(params[:knowledge_base_id]) do
        {:ok, details} -> details
        {:error, _} -> %{kb_version_id: nil, status: :ready, vector_store_id: nil}
      end

    attrs = %{
      temperature: params[:temperature] || 1,
      model: params[:model] || @default_model,
      organization_id: org_id,
      instructions: prompt,
      name: generate_temp_name(params[:name], "Assistant"),
      vector_store_ids:
        if(kb_details.vector_store_id,
          do: [kb_details.vector_store_id],
          else: []
        )
    }

    with {:ok, kaapi_response} <- Kaapi.create_assistant_config(attrs, org_id),
         kaapi_uuid when is_binary(kaapi_uuid) <- kaapi_response.data.id,
         {:ok, assistant} <-
           Assistants.create_assistant(%{
             name: attrs.name,
             description: params[:description],
             kaapi_uuid: kaapi_uuid,
             organization_id: org_id
           }),
         {:ok, config_version} <-
           AssistantConfigVersion.create_assistant_config_version(%{
             assistant_id: assistant.id,
             prompt: prompt,
             model: attrs.model,
             provider: "kaapi",
             settings: %{temperature: attrs.temperature},
             status: kb_details.status,
             organization_id: org_id
           }),
         {:ok, updated_assistant} <-
           Assistants.update_assistant_active_config(
             assistant.id,
             config_version.id
           ) do
      if kb_details.kb_version_id do
        link_config_to_kb(config_version.id, kb_details.kb_version_id, org_id)
      end

      {:ok, %{assistant: updated_assistant, config_version: config_version}}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, %{status: _status, body: body}} when is_map(body) ->
        {:error, "Failed to create assistant config in Kaapi: #{body[:error]}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "Failed to create assistant: #{inspect(reason)}"}

      _ ->
        {:error, "Failed to create assistant: Something went wrong"}
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

      Kaapi.delete_assistant(assistant.assistant_id, assistant.organization_id)

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
         {:ok, openai_response} <-
           ApiClient.modify_assistant(assistant.assistant_id, params) do
      Kaapi.update_assistant(openai_response, params.organization_id)

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

  @doc """
  Imports existing assistants from openAI to Glific platform.
  """
  @spec import_assistant(String.t(), integer()) :: {:ok, map()} | {:error, any()}
  def import_assistant(assistant_id, org_id) do
    Repo.put_process_state(org_id)

    with {:ok, assistant_data} <- ApiClient.retrieve_assistant(assistant_id),
         {:ok, _} <- filesearch_enabled?(assistant_data) do
      vector_store_id = List.first(assistant_data.tool_resources.file_search.vector_store_ids)

      if is_nil(vector_store_id) do
        create_assistant(assistant_id, assistant_data)
      else
        create_assistant_and_vector_store(vector_store_id, assistant_data)
      end
    end
  end

  @spec create_assistant(String.t(), map()) :: {:ok, map()} | {:error, any()}
  defp create_assistant(assistant_id, assistant_data) do
    Assistant.create_assistant(
      %{
        assistant_id: assistant_id,
        inserted_at: DateTime.from_unix!(assistant_data.created_at),
        organization_id: Repo.get_organization_id()
      }
      |> Map.merge(assistant_data)
    )
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

  @spec filesearch_enabled?(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp filesearch_enabled?(%{tool_resources: %{file_search: _}}), do: {:ok, "enabled"}

  defp filesearch_enabled?(_),
    do: {:error, "Please enable filesearch for this assistant"}

  @spec create_assistant_and_vector_store(String.t(), map()) ::
          {:ok, map()} | {:error, String.t()}
  defp create_assistant_and_vector_store(vector_store_id, assistant_data) do
    with {:ok, vector_store_data} <- ApiClient.retrieve_vector_store(vector_store_id),
         {:ok, %{data: vector_store_files}} <-
           ApiClient.retrieve_vector_store_files(vector_store_id) do
      case retrieve_vector_store_files(vector_store_files) do
        :error ->
          {:error, "Failed to retrieve file"}

        vs_files_info ->
          vector_store_data = Map.put(vector_store_data, :vs_files_info, vs_files_info)
          create_filesearch_artifacts_on_import(assistant_data, vector_store_data)
      end
    end
  end

  # We halt and error out, if we get an api error while retrieving the file details
  # Since we don't want partial data in DB
  @spec retrieve_vector_store_files(list()) :: map() | :error
  defp retrieve_vector_store_files(vector_store_files) do
    Enum.reduce_while(vector_store_files, %{}, fn vs_file, file_info ->
      if vs_file.status in ["completed", "pending"] do
        case ApiClient.retrieve_file(vs_file.id) do
          {:ok, file} ->
            {:cont,
             Map.put(file_info, file.id, %{
               file_id: file.id,
               filename: file.filename,
               uploaded_at: DateTime.from_unix!(file.created_at) |> DateTime.to_iso8601()
             })}

          _ ->
            {:halt, :error}
        end
      else
        {:cont, file_info}
      end
    end)
  end

  defp create_filesearch_artifacts_on_import(assistant_data, vector_store_data) do
    Multi.new()
    |> Multi.run(:create_vector_store, fn _, _ ->
      VectorStore.upsert_vector_store(
        %{
          vector_store_id: vector_store_data.id,
          inserted_at: DateTime.from_unix!(vector_store_data.created_at),
          organization_id: Repo.get_organization_id(),
          size: vector_store_data.usage_bytes,
          files: vector_store_data.vs_files_info
        }
        |> Map.merge(vector_store_data)
      )
    end)
    |> Multi.run(:create_assistant, fn _, %{create_vector_store: vector_store} ->
      Assistant.create_assistant(
        %{
          assistant_id: assistant_data.id,
          inserted_at: DateTime.from_unix!(assistant_data.created_at),
          organization_id: Repo.get_organization_id(),
          vector_store_id: vector_store.id
        }
        |> Map.merge(assistant_data)
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create_assistant: assistant}} ->
        {:ok, assistant}

      {:error, _, err, _} ->
        Logger.error("Error on importing assistant due to #{inspect(err)}")
        {:error, "Error on importing assistant"}
    end
  end

  @spec validate_file_format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_file_format(filename) do
    extension = String.split(filename, ".") |> List.last()

    if extension in @assistant_supported_file_extensions do
      {:ok, filename}
    else
      {:error, "Files with extension '.#{extension}' not supported in Filesearch"}
    end
  end

  @spec link_config_to_kb(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), nil | [term()]}
  defp link_config_to_kb(config_version_id, kb_version_id, org_id) do
    Repo.insert_all(
      "assistant_config_version_knowledge_base_versions",
      [
        %{
          assistant_config_version_id: config_version_id,
          knowledge_base_version_id: kb_version_id,
          organization_id: org_id,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ]
    )
  end

  @spec get_kb_details(nil | integer()) :: {:ok, map()} | {:error, any()}
  defp get_kb_details(nil) do
    {:ok, %{kb_version_id: nil, status: :ready, vector_store_id: nil}}
  end

  defp get_kb_details(kb_id) do
    case KnowledgeBaseVersion.get_knowledge_base_version(kb_id) do
      {:ok, kb_version} ->
        status = if kb_version.status == :completed, do: :ready, else: :in_progress

        {:ok,
         %{
           kb_version_id: kb_version.id,
           status: status,
           vector_store_id: kb_version.llm_service_id
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
