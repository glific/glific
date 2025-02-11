defmodule GlificWeb.FlowResumeController do
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

    with {:ok, contact} <-
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
end
