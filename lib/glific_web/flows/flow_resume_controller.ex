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

  @doc """
  Implementation of resuming the flow after the flow was waiting for result from 3rd party service
  """
  @spec flow_resume_with_results(Plug.Conn.t(), map) :: Plug.Conn.t()
  def flow_resume_with_results(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        result
      ) do
    with_callback_trace("Kaapi Flow Resume Callback", result, fn ->
      response =
        Appsignal.instrument("Kaapi Callback Parse", "kaapi.callback.parse", fn ->
          result |> parse_callback_response() |> maybe_upload_tts_audio()
        end)

      organization =
        Appsignal.instrument("Kaapi Callback Load Organization", "db.query", fn ->
          Partners.organization(organization_id)
        end)

      Repo.put_process_state(organization.id)

      log_message = %{
        success: result["success"],
        message: response["message"] || result["error"],
        error_type: result["error_type"],
        reason: result["reason"],
        thread_id: response["thread_id"]
      }

      if response["webhook_log_id"] do
        Appsignal.instrument("Kaapi Callback Update WebhookLog", "db.query", fn ->
          Webhook.update_log(response["webhook_log_id"], log_message)
        end)
      end

      response_key = response["result_name"] || "response"

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

      track_kaapi_latency(response)

      with true <- validate_request(organization_id, response),
           {:ok, contact} <-
             Appsignal.instrument("Kaapi Callback Fetch Contact", "db.query", fn ->
               Repo.fetch_by(Contact, %{
                 id: response["contact_id"],
                 organization_id: organization.id
               })
             end) do
        Appsignal.instrument("Kaapi Callback Resume Flow", "kaapi.callback.resume_flow", fn ->
          FlowContext.resume_contact_flow(
            contact,
            response["flow_id"],
            %{response_key => response},
            message
          )
        end)
      end
    end)

    json(conn, "")
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
    Task.start(fn ->
      Repo.put_process_state(organization_id)

      with_callback_trace("Kaapi Voice Callback", result, fn ->
        response =
          Appsignal.instrument("Kaapi Voice Callback Parse", "kaapi.callback.parse", fn ->
            parse_callback_response(result)
          end)

        do_voice_flow_resume(organization_id, result, response)
      end)
    end)

    json(conn, "")
  end

  @spec do_voice_flow_resume(non_neg_integer(), map(), map()) :: :ok
  defp do_voice_flow_resume(organization_id, result, response) do
    organization =
      Appsignal.instrument("Kaapi Voice Load Organization", "db.query", fn ->
        Partners.organization(organization_id)
      end)

    response_key = response["result_name"] || "response"

    message =
      if result["success"],
        do: Messages.create_temp_message(organization_id, "Success"),
        else: Messages.create_temp_message(organization_id, "Failure")

    with true <- validate_request(organization_id, response),
         {:ok, contact} <-
           Appsignal.instrument("Kaapi Voice Fetch Contact", "db.query", fn ->
             Repo.fetch_by(Contact, %{
               id: response["contact_id"],
               organization_id: organization.id
             })
           end) do
      voice_response =
        Appsignal.instrument(
          "Kaapi Voice Post Process",
          "kaapi.callback.voice_post_process",
          fn ->
            CommonWebhook.voice_post_process(organization_id, result["success"], response)
          end
        )

      if response["webhook_log_id"],
        do:
          Appsignal.instrument("Kaapi Voice Update WebhookLog", "db.query", fn ->
            Webhook.update_log(response["webhook_log_id"], voice_response)
          end)

      track_kaapi_latency(response)

      Appsignal.instrument("Kaapi Voice Resume Flow", "kaapi.callback.resume_flow", fn ->
        FlowContext.resume_contact_flow(
          contact,
          response["flow_id"],
          %{response_key => voice_response},
          message
        )
      end)
    else
      false ->
        Logger.warning("Voice flow resume validation failed for org #{organization_id}")

      {:error, reason} ->
        Logger.warning("Voice flow resume contact lookup failed: #{inspect(reason)}")
    end

    :ok
  end

  # New format from unified-llm-call (/api/v1/llm/call):
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

  @spec track_kaapi_latency(map()) :: :ok
  defp track_kaapi_latency(%{"timestamp" => timestamp, "call_type" => call_type})
       when is_integer(timestamp) do
    now = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    duration_ms = (now - timestamp) / 1_000

    Appsignal.add_distribution_value("kaapi_llm_latency", duration_ms, %{
      call_type: call_type
    })
  end

  defp track_kaapi_latency(_response), do: :ok

  @spec with_callback_trace(String.t(), map(), (-> any())) :: any()
  defp with_callback_trace(name, result, fun) do
    trace_ctx = extract_trace_context(result)
    sample_data = Map.merge(trace_data(result), trace_ctx)

    Appsignal.instrument(name, "kaapi.callback", fn span ->
      Appsignal.Span.set_sample_data(span, "meta", sample_data)
      fun.()
    end)
  end

  @spec trace_data(map()) :: map()
  defp trace_data(%{"metadata" => metadata}) do
    %{
      organization_id: metadata["organization_id"],
      flow_id: metadata["flow_id"],
      contact_id: metadata["contact_id"],
      webhook_log_id: metadata["webhook_log_id"],
      call_type: metadata["call_type"]
    }
  end

  defp trace_data(_), do: %{}

  @spec extract_trace_context(map()) :: map()
  defp extract_trace_context(result) do
    metadata_trace = get_in(result, ["metadata", "trace_context"]) || result["trace_context"]

    case metadata_trace do
      %{"correlation_id" => correlation_id} -> %{correlation_id: correlation_id}
      %{correlation_id: correlation_id} -> %{correlation_id: correlation_id}
      _ -> %{}
    end
  end

  @spec validate_request(non_neg_integer(), map()) :: boolean()
  defp validate_request(new_organization_id, fields) do
    flow_id = fields["flow_id"]
    contact_id = fields["contact_id"]
    organization_id = fields["organization_id"]
    timestamp = fields["timestamp"]
    signature = fields["signature"]

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
