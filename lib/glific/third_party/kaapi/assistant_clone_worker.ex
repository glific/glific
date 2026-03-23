defmodule Glific.ThirdParty.Kaapi.AssistantCloneWorker do
  @moduledoc """
  Worker for cloning an assistant by creating a new assistant with the same
  configuration (model, prompt, knowledge base) and prefixing "Copy of"
  to the assistant name.
  """

  use Oban.Worker,
    queue: :clone_assistant,
    max_attempts: 2

  require Logger

  alias Glific.{
    Assistants,
    Assistants.Assistant,
    Assistants.KnowledgeBaseVersion,
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
  def perform(%Oban.Job{
        args: %{"assistant_id" => assistant_id, "organization_id" => organization_id}
      }) do
    Repo.put_process_state(organization_id)

    with {:ok, assistant} <- Repo.fetch_by(Assistant, %{id: assistant_id}),
         assistant <- Repo.preload(assistant, active_config_version: :knowledge_base_versions),
         {:ok, knowledge_base_version} <- get_knowledge_base_version(assistant),
         params <- assistant_params(assistant, organization_id),
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
         file_ids = Enum.map(file_data, & &1.file_id),
         {:ok, %{data: %{job_id: job_id}}} <-
           Kaapi.create_collection(%{documents: file_ids}, organization_id),
         {:ok, llm_service_id} <- poll_kaapi_for_collection_status(job_id, organization_id) do
      Logger.info(
        "AssistantCloneWorker: Successfully cloned assistant #{assistant_id} for org #{organization_id}"
      )

      :ok
    else
      {:error, reason} ->
        Logger.error(
          "AssistantCloneWorker: Failed to clone assistant #{assistant_id} for org #{organization_id}: #{inspect(reason)}"
        )

        {:error, inspect(reason)}

      :error ->
        Logger.error(
          "AssistantCloneWorker: Failed to clone assistant #{assistant_id} for org #{organization_id}"
        )

        {:error, "Failed to clone assistant"}
    end
  end

  @spec get_knowledge_base_version(Assistant.t()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, String.t()}
  defp get_knowledge_base_version(assistant) do
    case assistant.active_config_version.knowledge_base_versions do
      [knowledge_base_version | _] -> {:ok, knowledge_base_version}
      [] -> {:error, "No knowledge base version found"}
    end
  end

  @spec assistant_params(Assistant.t(), non_neg_integer()) :: map()
  defp assistant_params(assistant, organization_id) do
    active_config = assistant.active_config_version

    %{
      name: "Copy of #{assistant.name}",
      prompt: active_config.prompt,
      model: active_config.model,
      temperature: get_in(active_config.settings || %{}, ["temperature"]) || 1,
      description: "Cloned version",
      organization_id: organization_id
    }
  end

  defp list_all_files(vector_store_id) do
    list_files_page(vector_store_id, nil, [])
  end

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

  defp download_files(files, vector_store_id, assistant_name, organization_id) do
    results =
      Enum.map(files, fn file ->
        download_file(file, vector_store_id, assistant_name, organization_id)
      end)

    succeeded = Enum.count(results, &(&1 == :ok))
    failed = length(results) - succeeded

    Logger.info(
      "File downloads for #{assistant_name} done. #{succeeded} downloaded, #{failed} failed"
    )

    :ok
  end

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

  defp upload_files_to_kaapi(assistant_name, organization_id) do
    path = Path.join(System.tmp_dir!(), "clone/#{organization_id}/#{assistant_name}")

    path
    |> File.ls!()
    |> Enum.map(fn filename ->
      file_path = Path.join(path, filename)

      case upload_document(file_path, organization_id) do
        {:ok, %{data: document_data}} ->
          Logger.info("File #{filename} uploaded for #{assistant_name}")

          %{
            file_id: document_data[:id],
            filename: filename,
            uploaded_at: document_data[:inserted_at],
            file_size: File.stat!(file_path).size
          }

        {:error, reason} ->
          Logger.error("FAILED (upload document error for #{assistant_name}): #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&(&1 == nil))
  end

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

  defp poll_kaapi_for_collection_status(
         collection_job_id,
         organization_id,
         backoff_ms,
         start_time_ms
       ) do
    case Kaapi.get_collection_status(collection_job_id, organization_id) do
      {:ok, %{status: "SUCCESFUL", collection: %{knowledge_base_id: kb_id}}} ->
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

  defp auth_headers() do
    api_key = Glific.get_open_ai_key()

    [
      {"authorization", "Bearer #{api_key}"},
      {"openai-beta", "assistants=v2"}
    ]
  end
end
