defmodule Glific.ThirdParty.Kaapi.AssistantCloneWorker do
  @moduledoc """
  Worker for cloning an assistant by creating a new assistant with the same
  configuration (model, prompt, knowledge base) and prefixing "Copy of"
  to the assistant name.
  """

  use Oban.Worker,
    queue: :clone_assistant,
    max_attempts: 2,
    unique: [
      fields: [:args],
      keys: [:assistant_id, :version_id, :organization_id],
      period: :infinity,
      states: [:available, :scheduled, :retryable, :executing]
    ]

  require Logger

  import Ecto.Query

  alias Glific.{
    Assistants,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBaseVersion,
    Notifications,
    Repo,
    ThirdParty.Kaapi
  }

  @base_url "https://api.openai.com/v1"
  @page_limit 100
  @max_poll_duration_ms 20 * 60 * 1_000
  @initial_backoff_ms 5_000
  @max_backoff_ms 60_000

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()}

  def perform(
        %Oban.Job{
          args: %{
            "assistant_id" => assistant_id,
            "version_id" => version_id,
            "organization_id" => organization_id,
            "is_legacy" => false
          },
          attempt: attempt,
          max_attempts: max_attempts
        } = _job
      ) do
    Repo.put_process_state(organization_id)

    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: assistant_id}),
         {:ok, source_version} <- Repo.fetch_by(AssistantConfigVersion, %{id: version_id}),
         source_version <- Repo.preload(source_version, :knowledge_base_versions),
         {:ok, kb_version} <- get_kb_version_from_config(source_version),
         name <- resolve_clone_name(assistant, source_version),
         params <-
           assistant_params(
             name,
             source_version,
             organization_id,
             extract_knowledge_base_ids(kb_version)
           ),
         {:ok, %{data: %{id: kaapi_uuid, version: %{version: kaapi_config_version}}}} <-
           Kaapi.create_assistant_config(params, organization_id),
         :ok <- create_cloned_assistant(params, kb_version, kaapi_uuid, kaapi_config_version) do
      update_clone_status(assistant, "")

      send_clone_notification(
        organization_id,
        "Assistant '#{assistant.name}' cloned successfully",
        :info
      )

      Logger.info(
        "AssistantCloneWorker: Successfully cloned non-legacy assistant #{assistant_id} " <>
          "(version #{version_id}) for org #{organization_id}"
      )

      :ok
    else
      {:error, reason} ->
        last_attempt? = attempt >= max_attempts
        handle_clone_failure(assistant_id, organization_id, reason, last_attempt?)
        {:error, inspect(reason)}
    end
  end

  def perform(
        %Oban.Job{
          args: %{
            "assistant_id" => assistant_id,
            "version_id" => _version_id,
            "organization_id" => organization_id,
            "is_legacy" => true
          },
          attempt: attempt,
          max_attempts: max_attempts
        } = _job
      ) do
    Repo.put_process_state(organization_id)

    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: assistant_id}),
         assistant <- Repo.preload(assistant, active_config_version: :knowledge_base_versions),
         {:ok, knowledge_base_version} <- get_knowledge_base_version(assistant),
         {:ok, files} <-
           list_all_files(knowledge_base_version.llm_service_id),
         :ok <-
           download_files(
             files,
             knowledge_base_version.llm_service_id,
             assistant.name,
             organization_id
           ),
         file_data <-
           upload_files_to_kaapi(assistant.name, organization_id),
         {:ok, file_ids} <- validate_uploaded_files(file_data),
         {:ok, %{data: %{job_id: job_id}}} <-
           Kaapi.create_collection(%{documents: file_ids}, organization_id),
         {:ok, llm_service_id} <- poll_kaapi_for_collection_status(job_id, organization_id),
         legacy_name <-
           resolve_clone_name(assistant, assistant.active_config_version),
         params <-
           assistant_params(
             legacy_name,
             assistant.active_config_version,
             organization_id,
             [llm_service_id]
           ),
         {:ok, %{data: %{id: kaapi_uuid, version: %{version: kaapi_config_version}}}} <-
           Kaapi.create_assistant_config(params, organization_id),
         {:ok, knowledge_base_version} <-
           create_cloned_knowledge_base(file_data, llm_service_id, job_id, organization_id),
         :ok <-
           create_cloned_assistant(
             params,
             knowledge_base_version,
             kaapi_uuid,
             kaapi_config_version
           ) do
      update_clone_status(assistant, "")

      send_clone_notification(
        organization_id,
        "Assistant '#{assistant.name}' cloned successfully",
        :info
      )

      Logger.info(
        "AssistantCloneWorker: Successfully cloned assistant #{assistant_id} for org #{organization_id}"
      )

      cleanup_temp_files(organization_id)
      :ok
    else
      {:error, reason} ->
        last_attempt? = attempt >= max_attempts
        handle_clone_failure(assistant_id, organization_id, reason, last_attempt?)
        cleanup_temp_files(organization_id)
        {:error, inspect(reason)}
    end
  end

  @spec handle_clone_failure(non_neg_integer(), non_neg_integer(), any(), boolean()) :: :ok
  defp handle_clone_failure(assistant_id, organization_id, reason, last_attempt?) do
    Logger.error(
      "AssistantCloneWorker: Failed to clone assistant #{assistant_id} for org #{organization_id}: #{inspect(reason)}"
    )

    if last_attempt? do
      case Repo.fetch_by(Assistant, %{id: assistant_id}) do
        {:ok, assistant} -> update_clone_status(assistant, "failed")
        _ -> :ok
      end

      send_clone_notification(
        organization_id,
        "Assistant cloning failed: #{inspect(reason)}",
        :warning
      )
    end

    :ok
  end

  @spec update_clone_status(Assistant.t(), String.t()) :: :ok
  defp update_clone_status(assistant, status) do
    assistant
    |> Ecto.Changeset.change(%{clone_status: status})
    |> Repo.update!()

    :ok
  end

  @spec send_clone_notification(non_neg_integer(), String.t(), atom()) :: :ok
  defp send_clone_notification(organization_id, message, severity) do
    Notifications.create_notification(%{
      category: "Assistant",
      message: message,
      severity: Map.get(Notifications.types(), severity),
      organization_id: organization_id,
      entity: %{type: "assistant_clone"}
    })

    :ok
  end

  @spec cleanup_temp_files(non_neg_integer()) :: :ok
  defp cleanup_temp_files(organization_id) do
    path = Path.join(System.tmp_dir!(), "clone/#{organization_id}")
    File.rm_rf(path)
    :ok
  end

  @spec get_knowledge_base_version(Assistant.t()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, String.t()}
  defp get_knowledge_base_version(assistant) do
    case assistant.active_config_version.knowledge_base_versions do
      [knowledge_base_version | _] -> {:ok, knowledge_base_version}
      [] -> {:error, "No knowledge base version found"}
    end
  end

  @spec validate_uploaded_files([map()]) :: {:ok, [String.t()]} | {:error, String.t()}
  defp validate_uploaded_files([]) do
    Logger.info("No files were uploaded successfully, cannot create collection")
    {:error, "No files were uploaded successfully, cannot create collection"}
  end

  defp validate_uploaded_files(file_data),
    do: {:ok, Enum.map(file_data, & &1.file_id)}

  @spec assistant_params(String.t(), AssistantConfigVersion.t(), non_neg_integer(), [String.t()]) ::
          map()
  defp assistant_params(name, config_version, organization_id, knowledge_base_ids) do
    %{
      name: name,
      prompt: config_version.prompt,
      model: config_version.model,
      temperature: get_in(config_version.settings, ["temperature"]) || 1,
      description: "Cloned version",
      organization_id: organization_id,
      knowledge_base_ids: knowledge_base_ids
    }
  end

  @spec resolve_clone_name(Assistant.t(), AssistantConfigVersion.t()) :: String.t()
  defp resolve_clone_name(assistant, config_version) do
    base_name = "Copy of #{assistant.name} Version #{config_version.version_number}"
    find_unique_name(base_name, 1)
  end

  @spec find_unique_name(String.t(), pos_integer()) :: String.t()
  defp find_unique_name(base_name, 1) do
    if assistant_name_taken?(base_name) do
      find_unique_name(base_name, 2)
    else
      base_name
    end
  end

  defp find_unique_name(base_name, n) do
    candidate = "#{base_name} (#{n})"

    if assistant_name_taken?(candidate) do
      find_unique_name(base_name, n + 1)
    else
      candidate
    end
  end

  @spec assistant_name_taken?(String.t()) :: boolean()
  defp assistant_name_taken?(name) do
    Assistant |> where([a], a.name == ^name) |> Repo.exists?()
  end

  @spec list_all_files(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  defp list_all_files(vector_store_id) do
    list_files_page(vector_store_id, nil, [])
  end

  @spec list_files_page(String.t(), String.t() | nil, [map()]) ::
          {:ok, [map()]} | {:error, String.t()}
  defp list_files_page(vector_store_id, after_cursor, acc) do
    params = [limit: @page_limit] ++ if(after_cursor, do: [after: after_cursor], else: [])

    case Req.get(
           "#{@base_url}/vector_stores/#{vector_store_id}/files",
           headers: auth_headers(),
           params: params
         ) do
      {:ok, %{status: 200, body: %{"data" => data, "has_more" => has_more}}} ->
        all = acc ++ data

        if has_more do
          last_id = List.last(data)["id"]
          list_files_page(vector_store_id, last_id, all)
        else
          Logger.info("Found #{length(all)} file(s)")
          {:ok, all}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to list vector store files (HTTP #{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request error listing files: #{inspect(reason)}"}
    end
  end

  @spec download_files([map()], String.t(), String.t(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  defp download_files(files, vector_store_id, assistant_name, organization_id) do
    results =
      Enum.map(files, fn file ->
        {file["id"], download_file(file, vector_store_id, assistant_name, organization_id)}
      end)

    failed_files =
      results
      |> Enum.filter(fn {_id, result} -> result == :error end)
      |> Enum.map(fn {id, _} -> id end)

    succeeded = length(results) - length(failed_files)

    Logger.info(
      "File downloads for #{assistant_name} done. #{succeeded} downloaded, #{length(failed_files)} failed"
    )

    if succeeded == 0 and length(files) > 0 do
      {:error,
       "#{length(failed_files)} file downloads failed for #{assistant_name}: #{Enum.join(failed_files, ", ")}"}
    else
      :ok
    end
  end

  @spec download_file(map(), String.t(), String.t(), non_neg_integer()) :: :ok | :error
  defp download_file(%{"id" => file_id} = _file, vector_store_id, assistant_name, organization_id) do
    Logger.info("Fetching metadata for #{file_id}")

    case Req.get("#{@base_url}/vector_stores/#{vector_store_id}/files/#{file_id}",
           headers: auth_headers()
         ) do
      {:ok, %{status: 200, body: %{"filename" => filename} = _meta}} ->
        fetch_and_save(file_id, filename, vector_store_id, assistant_name, organization_id)

      {:ok, %{status: 200, body: meta}} ->
        # Fallback filename if "filename" key is missing
        filename = meta["filename"] || "#{file_id}.md"
        fetch_and_save(file_id, filename, vector_store_id, assistant_name, organization_id)

      {:ok, %{status: status, body: body}} ->
        # Handle the error case when file download fails
        Logger.error("FAILED (metadata HTTP #{status}): #{inspect(body)}")
        :error

      {:error, reason} ->
        # Handle the error case when file download fails
        Logger.error("FAILED (metadata request error): #{inspect(reason)}")
        :error
    end
  end

  @spec fetch_and_save(String.t(), String.t(), String.t(), String.t(), non_neg_integer()) ::
          :ok | :error
  defp fetch_and_save(file_id, filename, vector_store_id, assistant_name, organization_id) do
    case Req.get("#{@base_url}/vector_stores/#{vector_store_id}/files/#{file_id}/content",
           headers: auth_headers()
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        content =
          data
          |> Enum.filter(&(&1["type"] == "text"))
          |> Enum.map_join("\n", & &1["text"])

        dest =
          Path.join(System.tmp_dir!(), "clone/#{organization_id}/#{assistant_name}/#{filename}")

        File.mkdir_p!(Path.dirname(dest))
        File.write!(dest, content)
        Logger.info("-> saved (#{byte_size(content)} bytes)")
        :ok

      {:ok, %{status: status, body: body}} ->
        # Handle the error case when file save fails
        Logger.error("FAILED (content HTTP #{status}): #{inspect(body)}")
        :error

      {:error, reason} ->
        # Handle the error case when file save fails
        Logger.error("FAILED (content request error): #{inspect(reason)}")
        :error
    end
  end

  @spec upload_files_to_kaapi(String.t(), non_neg_integer()) :: [map()]
  defp upload_files_to_kaapi(assistant_name, organization_id) do
    path = Path.join(System.tmp_dir!(), "clone/#{organization_id}/#{assistant_name}")
    File.mkdir_p!(path)

    results =
      path
      |> File.ls!()
      |> Enum.map(fn filename ->
        file_path = Path.join(path, filename)

        case upload_document(file_path, organization_id) do
          {:ok, %{data: document_data}} ->
            Logger.info("File #{filename} uploaded for #{assistant_name}")

            {:ok,
             %{
               file_id: document_data[:id],
               filename: filename,
               uploaded_at: document_data[:inserted_at],
               file_size: File.stat!(file_path).size
             }}

          {:error, reason} ->
            Logger.error(
              "FAILED (upload document error for #{assistant_name}): #{inspect(reason)}"
            )

            {:error, filename}
        end
      end)

    failed_files = for {:error, filename} <- results, do: filename

    if failed_files != [] do
      send_clone_notification(
        organization_id,
        "Failed to upload #{length(failed_files)} file(s) during cloning of '#{assistant_name}': #{Enum.join(failed_files, ", ")}",
        :warning
      )
    end

    for {:ok, file_data} <- results, do: file_data
  end

  @spec upload_document(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, any()}
  defp upload_document(file, organization_id) do
    document_params = %{path: file, filename: Path.basename(file)}
    Kaapi.upload_document(document_params, organization_id)
  end

  @spec poll_kaapi_for_collection_status(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp poll_kaapi_for_collection_status(collection_job_id, organization_id) do
    poll_kaapi_for_collection_status(
      collection_job_id,
      organization_id,
      @initial_backoff_ms,
      System.monotonic_time(:millisecond)
    )
  end

  @spec poll_kaapi_for_collection_status(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, String.t()} | {:error, String.t()}
  defp poll_kaapi_for_collection_status(
         collection_job_id,
         organization_id,
         backoff_ms,
         start_time_ms
       ) do
    case Kaapi.get_collection_status(collection_job_id, organization_id) do
      {:ok, %{status: "SUCCESSFUL", collection: %{knowledge_base_id: kb_id}}} ->
        Logger.info(
          "AssistantCloneWorker: Collection #{collection_job_id} is SUCCESFUL, kb_id: #{kb_id}"
        )

        {:ok, kb_id}

      {:ok, %{status: status}} ->
        elapsed_ms = System.monotonic_time(:millisecond) - start_time_ms

        if elapsed_ms + backoff_ms >= @max_poll_duration_ms do
          Logger.error(
            "AssistantCloneWorker: Polling timed out for collection #{collection_job_id}, last status: #{status}"
          )

          {:error, "Polling timed out after 20 minutes, last status: #{status}"}
        else
          Logger.info(
            "AssistantCloneWorker: Collection #{collection_job_id} status: #{status}, retrying in #{backoff_ms}ms"
          )

          Process.sleep(backoff_ms)
          next_backoff = min(backoff_ms * 2, @max_backoff_ms)

          poll_kaapi_for_collection_status(
            collection_job_id,
            organization_id,
            next_backoff,
            start_time_ms
          )
        end

      {:error, reason} ->
        Logger.error(
          "AssistantCloneWorker: Failed to get collection status for #{collection_job_id}: #{inspect(reason)}"
        )

        {:error, inspect(reason)}
    end
  end

  @spec create_cloned_knowledge_base([map()], String.t(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, any()}
  defp create_cloned_knowledge_base(file_data, llm_service_id, kaapi_job_id, organization_id) do
    files =
      Enum.reduce(file_data, %{}, fn file, acc ->
        Map.put(acc, file.file_id, file)
      end)

    total_size = Enum.reduce(file_data, 0, fn file, acc -> acc + (file.file_size || 0) end)

    with {:ok, kb} <-
           Assistants.create_knowledge_base(%{
             name: "Cloned-KB-#{Ecto.UUID.generate() |> String.split("-") |> List.first()}",
             organization_id: organization_id
           }),
         {:ok, kb_version} <-
           Assistants.create_knowledge_base_version(%{
             knowledge_base_id: kb.id,
             organization_id: organization_id,
             files: files,
             size: total_size,
             status: :completed,
             llm_service_id: llm_service_id,
             kaapi_job_id: kaapi_job_id
           }) do
      Logger.info("Created cloned KB #{kb.id} with version #{kb_version.id}")
      {:ok, kb_version}
    end
  end

  @spec create_cloned_assistant(
          map(),
          KnowledgeBaseVersion.t() | nil,
          String.t(),
          non_neg_integer()
        ) :: :ok | {:error, any()}
  defp create_cloned_assistant(params, knowledge_base_version, kaapi_uuid, kaapi_config_version) do
    with {:ok, assistant} <- create_assistant(params, kaapi_uuid),
         {:ok, assistant_version} <-
           create_assistant_version(assistant, params, kaapi_config_version),
         {:ok, _assistant} <- set_active_config_version(assistant, assistant_version) do
      if knowledge_base_version do
        link_assistant_version_and_knowledge_base(
          assistant_version,
          knowledge_base_version,
          params
        )
      end

      :ok
    end
  end

  @spec create_assistant(map(), String.t()) :: {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  defp create_assistant(params, kaapi_uuid) do
    Assistant.changeset(%Assistant{}, %{
      name: params.name,
      organization_id: params.organization_id,
      kaapi_uuid: kaapi_uuid
    })
    |> Repo.insert()
  end

  @spec create_assistant_version(Assistant.t(), map(), non_neg_integer()) ::
          {:ok, AssistantConfigVersion.t()} | {:error, Ecto.Changeset.t()}
  defp create_assistant_version(assistant, params, kaapi_config_version) do
    AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
      assistant_id: assistant.id,
      description: params.description,
      prompt: params.prompt,
      model: params.model,
      provider: "openai",
      settings: %{temperature: params.temperature},
      status: :ready,
      organization_id: params.organization_id,
      kaapi_version_number: kaapi_config_version
    })
    |> Repo.insert()
  end

  @spec set_active_config_version(Assistant.t(), AssistantConfigVersion.t()) ::
          {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  defp set_active_config_version(assistant, assistant_version) do
    Assistant.set_active_config_version_changeset(assistant, %{
      active_config_version_id: assistant_version.id
    })
    |> Repo.update()
  end

  @spec link_assistant_version_and_knowledge_base(
          AssistantConfigVersion.t(),
          KnowledgeBaseVersion.t(),
          map()
        ) :: {non_neg_integer(), nil | [term()]} | {:error, Ecto.Changeset.t()}
  defp link_assistant_version_and_knowledge_base(
         assistant_version,
         knowledge_base_version,
         params
       ) do
    entries = [
      %{
        assistant_config_version_id: assistant_version.id,
        knowledge_base_version_id: knowledge_base_version.id,
        organization_id: params.organization_id,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ]

    Repo.insert_all("assistant_config_version_knowledge_base_versions", entries)
  end

  @spec extract_knowledge_base_ids(KnowledgeBaseVersion.t() | nil) :: [String.t()]
  defp extract_knowledge_base_ids(nil), do: []
  defp extract_knowledge_base_ids(kb_version), do: [kb_version.llm_service_id]

  @spec get_kb_version_from_config(AssistantConfigVersion.t()) ::
          {:ok, KnowledgeBaseVersion.t() | nil}
  defp get_kb_version_from_config(config_version) do
    case config_version.knowledge_base_versions do
      [kb_version | _] -> {:ok, kb_version}
      [] -> {:ok, nil}
    end
  end

  @spec auth_headers :: [tuple()]
  defp auth_headers do
    api_key = Glific.get_open_ai_key()

    [
      {"authorization", "Bearer #{api_key}"},
      {"openai-beta", "assistants=v2"}
    ]
  end
end
