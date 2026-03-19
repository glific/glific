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
    response = result |> parse_callback_response() |> maybe_upload_tts_audio()

    organization = Partners.organization(organization_id)
    Repo.put_process_state(organization.id)

    message =
      %{
        success: result["success"],
        message: response["message"] || result["error"],
        error_type: result["error_type"],
        reason: result["reason"],
        thread_id: response["thread_id"]
      }

    if response["webhook_log_id"], do: Webhook.update_log(response["webhook_log_id"], message)
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
           Repo.fetch_by(Contact, %{
             id: response["contact_id"],
             organization_id: organization.id
           }) do
      FlowContext.resume_contact_flow(
        contact,
        response["flow_id"],
        %{response_key => response},
        message
      )
    end

    # always return 200 and an empty response
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
    response = parse_callback_response(result)

    Task.start(fn ->
      Repo.put_process_state(organization_id)
      do_voice_flow_resume(organization_id, result, response)
    end)

    json(conn, "")
  end

  @spec do_voice_flow_resume(non_neg_integer(), map(), map()) :: :ok
  defp do_voice_flow_resume(organization_id, result, response) do
    organization = Partners.organization(organization_id)

    voice_response =
      CommonWebhook.voice_post_process(organization_id, result["success"], response)

    if response["webhook_log_id"],
      do: Webhook.update_log(response["webhook_log_id"], voice_response)

    response_key = response["result_name"] || "response"

    message =
      if result["success"],
        do: Messages.create_temp_message(organization_id, "Success"),
        else: Messages.create_temp_message(organization_id, "Failure")

    with true <- validate_request(organization_id, response),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{
             id: response["contact_id"],
             organization_id: organization.id
           }) do
      FlowContext.resume_contact_flow(
        contact,
        response["flow_id"],
        %{response_key => voice_response},
        message
      )
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
