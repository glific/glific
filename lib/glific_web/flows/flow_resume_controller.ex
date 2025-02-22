defmodule GlificWeb.Flows.FlowResumeController do
  @moduledoc """
  The controller to process events received from 3rd party services to resume the flow
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.{Contacts.Contact, Flows.FlowContext, Partners, Repo}

  @doc """
  Implementation of resuming the flow after the flow was waiting for result from 3rd party service
  """
  @spec flow_resume_with_results(Plug.Conn.t(), map) :: Plug.Conn.t()
  def flow_resume_with_results(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        response
      ) do
    organization = Partners.organization(organization_id)
    Repo.put_process_state(organization.id)

    # need to validate signature
    # need to validate timestamp

    with true <- validate_request(organization_id, response),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{
             id: response["contact_id"],
             organization_id: organization.id
           }) do
      FlowContext.resume_contact_flow(
        contact,
        response["flow_id"],
        %{response: response},
        nil
      )
    end

    # always return 200 and an empty response
    json(conn, "")
  end

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
