defmodule GlificWeb.Flows.FlowResumeController do
  @moduledoc """
  The controller to process events received from 3rd party services to resume the flow
  """

  use GlificWeb, :controller
  use Publicist
  require Logger

  alias Glific.{
    Clients.CommonWebhook,
    Contacts.Contact,
    Flows.FlowContext,
    Flows.Webhook,
    GCS.GcsWorker,
    Messages,
    Partners,
    Repo
  }

  alias Glific.Flows.Webhooks.{Instrumentation, Registry}

  @doc """
  Implementation of resuming the flow after the flow was waiting for result from 3rd party service
  """
  @spec flow_resume(Plug.Conn.t(), map) :: Plug.Conn.t()
  def flow_resume(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        result
      ) do
    # uploading audio kept outside of task to avoid transferring large data between processes
    # https://elixirmerge.com/p/the-impact-of-data-transfer-on-performance-in-elixirs-task-async
    response = result |> parse_callback_response() |> maybe_upload_tts_audio()

    run_supervised(fn ->
      do_flow_resume(organization_id, result, response)
    end)

    json(conn, "")
  end

  @spec do_flow_resume(non_neg_integer(), map(), map()) :: :ok
  defp do_flow_resume(organization_id, result, response) do
    Repo.put_process_state(organization_id)
    organization = Partners.organization(organization_id)

    # Validate the callback signature BEFORE acting on it — only then do we touch the
    # webhook log, emit metrics, run the module's handle_resume/2, or resume the flow.
    # A forged/unsigned callback must not drive any of that.
    with true <- validate_request(organization_id, response),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{
             id: response["contact_id"],
             organization_id: organization.id
           }) do
      resume_validated_flow(organization_id, result, response, contact)
    else
      false ->
        Logger.warning(
          "Flow resume validation failed: organization_id=#{organization_id}, flow_id=#{response["flow_id"]}, contact_id=#{response["contact_id"]}, webhook_log_id=#{response["webhook_log_id"]}, result_name=#{response["result_name"]}, timestamp=#{response["timestamp"]}"
        )

      {:error, reason} ->
        Logger.warning("Flow resume contact lookup failed: #{inspect(reason)}")
    end

    :ok
  end

  @spec resume_validated_flow(non_neg_integer(), map(), map(), Contact.t()) :: :ok
  defp resume_validated_flow(organization_id, result, response, contact) do
    response_key = response["result_name"] || "response"

    log_message = %{
      success: result["success"],
      message: response["message"] || result["error"],
      error_type: result["error_type"],
      reason: result["reason"],
      thread_id: response["thread_id"]
    }

    if response["webhook_log_id"], do: Webhook.update_log(response["webhook_log_id"], log_message)

    message =
      case {result["success"], response["webhook_log_id"]} do
        {true, nil} ->
          Messages.create_temp_message(organization_id, "No Response")

        {true, _} ->
          Messages.create_temp_message(organization_id, "Success")

        {false, _} ->
          Messages.create_temp_message(organization_id, "Failure")

        _ ->
          # Sending nil so that it remains compatible with other webhook responses
          # (besides Kaapi) and falls back to the default behavior.
          nil
      end

    track_callback_outcome(result, response)

    # Resolve the module for this webhook (if registered) and call handle_resume/2
    # with the parsed (and TTS-uploaded) `response`. The raw callback success flag is
    # passed via ctx. Standard/unregistered nodes fall back to the parsed `response`.
    ctx = %{organization_id: organization_id, success: result["success"]}
    shaped_response = shape_resume_response(response, ctx)

    case FlowContext.resume_contact_flow(
           contact,
           response["flow_id"],
           %{response_key => shaped_response},
           message
         ) do
      {:ok, _context, _messages} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Flow resume failed for contact #{response["contact_id"]}, flow #{response["flow_id"]}: #{inspect(reason)}"
        )
    end

    :ok
  end

  @spec run_supervised((-> any())) :: :ok
  defp run_supervised(fun) do
    case Task.Supervisor.start_child(Glific.TaskSupervisor, fn ->
           run_supervised_task(fun)
         end) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Glific.log_exception(%RuntimeError{
          message: "Failed to start flow_resume supervised task: #{inspect(reason)}"
        })

        :ok
    end
  end

  @spec run_supervised_task((-> any())) :: :ok
  defp run_supervised_task(fun) do
    try do
      fun.()
    rescue
      exception ->
        Glific.log_exception(exception)
    end

    :ok
  end

  # Routes callback failure reporting through the centralised Instrumentation module
  # so all failure events share the same AppSignal namespace and tag shape.
  @spec maybe_report_callback_failure(map(), map()) :: :ok
  defp maybe_report_callback_failure(result, response) do
    Instrumentation.report_callback_failure(result, response)
  end

  # Shapes the parsed callback `response` via the registered webhook module's
  # handle_resume/2 (e.g. voice post-processing). Standard nodes have no module
  # or no handle_resume override and fall back to the parsed `response` unchanged.
  @spec shape_resume_response(map(), map()) :: map()
  defp shape_resume_response(response, ctx) do
    with module when is_atom(module) and not is_nil(module) <-
           Registry.lookup_by_webhook_name(response["webhook_name"]),
         true <- function_exported?(module, :handle_resume, 2),
         {:ok, shaped} <- module.handle_resume(response, ctx) do
      shaped
    else
      _ -> response
    end
  end

  # Resolves "voice-filesearch-gpt" and runs its handle_resume/2 (NMT+TTS voice
  # post-processing) on the parsed `response`. Falls back to voice_post_process/3 if
  # the module is missing or handle_resume returns an error.
  @spec shape_voice_response(non_neg_integer(), map(), map()) :: map()
  defp shape_voice_response(organization_id, result, response) do
    ctx = %{organization_id: organization_id, success: result["success"]}
    webhook_name = response["webhook_name"] || "voice-filesearch-gpt"

    with module when is_atom(module) and not is_nil(module) <-
           Registry.lookup_by_webhook_name(webhook_name),
         true <- function_exported?(module, :handle_resume, 2),
         {:ok, shaped} <- module.handle_resume(response, ctx) do
      shaped
    else
      _ -> CommonWebhook.voice_post_process(organization_id, result["success"], response)
    end
  end

  @doc """
  Callback for voice unified LLM calls.
  Receives the Kaapi LLM response, performs NMT+TTS (translate + generate audio),
  then resumes the flow with translated_text + media_url.
  """
  @spec voice_flow_resume(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def voice_flow_resume(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        result
      ) do
    response = parse_callback_response(result)

    run_supervised(fn ->
      do_voice_flow_resume(organization_id, result, response)
    end)

    json(conn, "")
  end

  @spec do_voice_flow_resume(non_neg_integer(), map(), map()) :: :ok
  defp do_voice_flow_resume(organization_id, result, response) do
    Repo.put_process_state(organization_id)
    organization = Partners.organization(organization_id)
    response_key = response["result_name"] || "response"

    # Validate BEFORE the expensive, side-effecting voice post-processing (NMT + TTS +
    # GCS upload in shape_voice_response). A forged callback must not trigger that work.
    with true <- validate_request(organization_id, response),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{
             id: response["contact_id"],
             organization_id: organization.id
           }) do
      message =
        if result["success"],
          do: Messages.create_temp_message(organization_id, "Success"),
          else: Messages.create_temp_message(organization_id, "Failure")

      voice_response = shape_voice_response(organization_id, result, response)

      if response["webhook_log_id"],
        do: Webhook.update_log(response["webhook_log_id"], voice_response)

      track_callback_outcome(result, response)

      case FlowContext.resume_contact_flow(
             contact,
             response["flow_id"],
             %{response_key => voice_response},
             message
           ) do
        {:ok, _context, _messages} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Voice flow resume failed for contact #{contact.id}, flow #{response["flow_id"]}: #{inspect(reason)}"
          )
      end
    else
      false ->
        Logger.warning(
          "Voice flow resume validation failed: organization_id=#{organization_id}, flow_id=#{response["flow_id"]}, contact_id=#{response["contact_id"]}, webhook_log_id=#{response["webhook_log_id"]}, result_name=#{response["result_name"]}, timestamp=#{response["timestamp"]}"
        )

      {:error, reason} ->
        Logger.warning("Voice flow resume contact lookup failed: #{inspect(reason)}")
    end

    :ok
  end

  # New format from filesearch-gpt (/api/v1/llm/call):
  # metadata (org_id, flow_id, signature, etc.) is in result["metadata"]
  # Map the response_id/conversation_id to thread_id, since we treat response_id as the thread ID in Glific
  # For TTS (output type "audio"), "message" holds the raw base64 and "output_type" is set
  # so that maybe_upload_tts_audio/1 can upload it to GCS and replace "message" with the media URL.
  @spec parse_callback_response(map()) :: map()
  defp parse_callback_response(%{"metadata" => metadata, "data" => data})
       when is_map(metadata) and map_size(metadata) > 0 do
    response_data = get_in(data || %{}, ["response"]) || %{}
    output = get_in(response_data, ["output"]) || %{}
    output_type = get_in(output, ["type"])
    conversation_id = response_data["conversation_id"]

    metadata
    |> Map.put("thread_id", conversation_id)
    |> Map.put("output_type", output_type)
    |> Map.put("message", get_in(output, ["content", "value"]))
  end

  # Old format from call_and_wait (/api/v1/responses):
  defp parse_callback_response(%{"data" => data}) do
    response = data || %{}
    Map.put(response, "thread_id", response["response_id"])
  end

  # Fallback for unexpected formats
  defp parse_callback_response(result) do
    Logger.warning(
      "Unexpected callback response format received from Kaapi or external service: #{inspect(result)}"
    )

    %{}
  end

  @spec maybe_upload_tts_audio(map()) :: map()
  defp maybe_upload_tts_audio(%{"output_type" => "audio", "message" => base64_audio} = response) do
    {:ok, organization_id} = response["organization_id"] |> Glific.parse_maybe_integer()
    media_url = upload_tts_audio(base64_audio, organization_id)

    response
    |> Map.put("message", media_url)
  end

  defp maybe_upload_tts_audio(response), do: response

  @spec upload_tts_audio(String.t() | nil, non_neg_integer()) :: String.t() | nil
  defp upload_tts_audio(nil, _organization_id), do: nil

  defp upload_tts_audio(base64_audio, organization_id) do
    uuid = Ecto.UUID.generate()
    remote_name = "Kaapi/outbound/#{uuid}.mp3"
    mp3_file = Path.join(System.tmp_dir!(), "#{uuid}.mp3")

    with {:ok, decoded_audio} <- Base.decode64(base64_audio),
         :ok <- File.write(mp3_file, decoded_audio),
         {:ok, media_meta} <- GcsWorker.upload_media(mp3_file, remote_name, organization_id) do
      File.rm(mp3_file)
      media_meta.url
    else
      error ->
        File.rm(mp3_file)
        Logger.error("Kaapi TTS upload failed: #{inspect(error)}")
        nil
    end
  end

  @spec track_callback_outcome(map(), map()) :: :ok
  defp track_callback_outcome(result, response) do
    status = if result["success"], do: "success", else: "failure"
    Webhook.track_webhook_count(response["webhook_name"], status)
    track_kaapi_latency(response, status)
    maybe_report_callback_failure(result, response)
  end

  # Records latency for an async webhook callback.
  @spec track_kaapi_latency(map(), String.t()) :: :ok
  defp track_kaapi_latency(%{"timestamp" => timestamp} = response, status)
       when is_integer(timestamp) do
    now = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    duration_ms = (now - timestamp) / 1_000

    case response["call_type"] do
      nil ->
        :ok

      call_type ->
        Appsignal.add_distribution_value("kaapi_llm_latency", duration_ms, %{
          call_type: call_type
        })
    end

    Webhook.track_webhook_latency(response["webhook_name"], status, duration_ms)
  end

  defp track_kaapi_latency(_response, _status), do: :ok

  @spec validate_request(non_neg_integer(), map()) :: boolean()
  defp validate_request(_new_organization_id, fields) when map_size(fields) == 0,
    do: false

  defp validate_request(new_organization_id, fields) do
    if missing_callback_fields?(fields),
      do: false,
      else: do_validate_request(new_organization_id, fields)
  end

  @spec missing_callback_fields?(map()) :: boolean()
  defp missing_callback_fields?(fields) do
    Enum.any?(
      ["organization_id", "flow_id", "contact_id", "timestamp", "signature"],
      &is_nil(Map.get(fields, &1))
    )
  end

  @spec do_validate_request(non_neg_integer(), map()) :: boolean()
  defp do_validate_request(new_organization_id, fields) do
    do_validate_signature(
      new_organization_id,
      fields["flow_id"],
      fields["contact_id"],
      fields["organization_id"],
      fields["timestamp"],
      fields["signature"]
    )
  end

  @spec do_validate_signature(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          integer(),
          String.t()
        ) :: boolean()
  defp do_validate_signature(
         new_organization_id,
         flow_id,
         contact_id,
         organization_id,
         timestamp,
         signature
       ) do
    signature_payload = %{
      "organization_id" => organization_id,
      "flow_id" => flow_id,
      "contact_id" => contact_id,
      "timestamp" => timestamp
    }

    new_signature =
      Glific.signature(
        organization_id,
        Jason.encode!(signature_payload),
        timestamp
      )

    new_timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    cond do
      new_organization_id != organization_id -> false
      new_signature != signature -> false
      new_timestamp > timestamp + 15 * 60 * 1_000_000 -> false
      true -> true
    end
  end
end
