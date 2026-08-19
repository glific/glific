defmodule GlificWeb.API.V1.SimulatorController do
  @moduledoc """
  Authenticated entry point for messages typed into the simulator.

  The simulator posts a message as though a contact had sent it. That used to go straight to
  the BSP webhook, which meant an unauthenticated request deciding an organization from the
  request host. Here the caller is authenticated and the organization comes from their token,
  so a user can only ever drive the simulator belonging to their own organization.

  Only simulator contacts are accepted; a payload naming any other sender is refused, so this
  cannot be used to forge a message from a real beneficiary.

  Beyond those checks the payload is handed to the usual Gupshup shunt, so every message type
  the simulator produces is handled exactly as an inbound message is.
  """

  use GlificWeb, :controller

  alias Glific.{Contacts, Repo, Users.User}
  alias GlificWeb.Providers.Gupshup.Plugs.Shunt

  @doc """
  Injects a simulator message into the inbound pipeline for the caller's organization.
  """
  @spec message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def message(conn, params) do
    %User{organization_id: organization_id} = conn.assigns[:current_user]

    if simulator_sender?(params) do
      Repo.put_organization_id(organization_id)

      conn
      |> assign(:organization_id, organization_id)
      |> Shunt.call(Shunt.init([]))
    else
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: %{status: 403, message: "Only simulator contacts can send simulator messages."}
      })
    end
  end

  @spec simulator_sender?(map()) :: boolean()
  defp simulator_sender?(%{"payload" => %{"sender" => %{"phone" => phone}}})
       when is_binary(phone),
       do: Contacts.simulator_contact?(phone)

  defp simulator_sender?(_params), do: false
end
