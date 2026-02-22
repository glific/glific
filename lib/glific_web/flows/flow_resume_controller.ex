defmodule GlificWeb.Flows.FlowResumeController do
  @moduledoc """
  The controller to process events received from 3rd party services to resume the flow
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.{Contacts.Contact, Flows.FlowContext, Flows.Webhook, Messages, Partners, Repo}

  @doc """
  Implementation of resuming the flow after the flow was waiting for result from 3rd party service
  """
  @spec flow_resume_with_results(Plug.Conn.t(), map) :: Plug.Conn.t()
  def flow_resume_with_results(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        result
      ) do
    response = parse_callback_response(result)

    organization = Partners.organization(organization_id)
    Repo.put_process_state(organization.id)

    message =
      %{
        success: result["success"],
        message: response["message"] || result["error"],
        thread_id: response["thread_id"]
      }

    if response["webhook_log_id"], do: Webhook.update_log(response["webhook_log_id"], message)
    respone_key = response["result_name"] || "response"

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

    with true <- validate_request(organization_id, response),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{
             id: response["contact_id"],
             organization_id: organization.id
           }) do
      FlowContext.resume_contact_flow(
        contact,
        response["flow_id"],
        %{respone_key => response},
        message
      )
    end

    # always return 200 and an empty response
    json(conn, "")
  end

  # New format from unified-llm-call (/api/v1/llm/call):
  # metadata (org_id, flow_id, signature, etc.) is in result["metadata"]
  # Map the response_id/conversation_id to thread_id, since we treat response_id as the thread ID in Glific
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

  # Old format from call_and_wait (/api/v1/responses):
  defp parse_callback_response(%{"data" => data}) do
    response = data || %{}
    Map.put(response, "thread_id", response["response_id"])
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
