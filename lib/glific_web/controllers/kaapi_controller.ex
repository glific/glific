defmodule GlificWeb.KaapiController do
  @moduledoc """
  The controller to process callbacks received from Kaapi.
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.Assistants
  alias Glific.Clients.CommonWebhook
  alias Glific.{Contacts.Contact, Flows.FlowContext, Flows.Webhook, Messages, Partners, Repo}

  @doc """
  Handles the callback from Kaapi upon successful or failure of collection creation.
  """
  @spec knowledge_base_version_creation_callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def knowledge_base_version_creation_callback(conn, params) do
    Logger.info("Received knowledge base creation callback", params: params)
    Assistants.handle_knowledge_base_callback(params)
    send_resp(conn, 200, "Knowledge base version creation callback handled successfully")
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

    {:ok, webhook_log_id} = Glific.parse_maybe_integer(response["webhook_log_id"])
    Webhook.update_log(webhook_log_id, voice_response)

    respone_key = response["result_name"] || "response"

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
        %{respone_key => voice_response},
        message
      )
    end

    :ok
  end

  @spec parse_callback_response(map()) :: map()
  defp parse_callback_response(%{"metadata" => metadata, "data" => data})
       when is_map(metadata) and map_size(metadata) > 0 do
    response_data = get_in(data || %{}, ["response"]) || %{}
    message_text = get_in(response_data, ["output", "content", "value"])
    conversation_id = response_data["conversation_id"]

    metadata
    |> Map.put("message", message_text)
    |> Map.put("thread_id", conversation_id)
  end

  defp parse_callback_response(result) do
    Logger.warning("Unexpected voice callback response format: #{inspect(result)}")
    %{}
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
