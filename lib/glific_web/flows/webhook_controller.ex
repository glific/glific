defmodule GlificWeb.Flows.WebhookController do
  @moduledoc """
  Experimental approach on trying to handle webhooks for NGOs within the system.
  This bypasses using a third party and hence makes things a lot more efficient
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.{Clients.Stir, Contacts, Flows}

  @doc """
  Example implementation of survey computation for STiR
  """
  @spec stir_survey(Plug.Conn.t(), map) :: Plug.Conn.t()
  def stir_survey(conn, %{"results" => results} = _params) do
    json =
      Stir.compute_survey_score(results)
      |> Map.merge(%{art_result: Stir.compute_art_results(results)})
      |> Map.merge(%{art_content: Stir.compute_art_content(results)})

    conn
    |> json(json)
  end

  @dg_call_to "09513886363"
  @dg_direction "incoming"
  @dg_glific_flow_id 1
  @dg_glific_organization_id 1

  @doc """
  First implementation of processing optin contact callback from exotel
  for digital green. Will need to make it more generic for broader use case
  across other NGOs

  We use the callto and directon parameters to ensure a valid call from exotel
  """
  @spec exotel_optin(Plug.Conn.t(), map) :: Plug.Conn.t()
  def exotel_optin(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        %{
          "CallFrom" => phone,
          "To" => @dg_call_to,
          "Direction" => @dg_direction,
        } = _params
  ) do
    if organization_id == @dg_glific_organization_id do
      # first create and optin the contact
      attrs = %{
        phone: phone,
        method: "Exotel",
        organization_id: organization_id
      }

      result = Contacts.optin_contact(attrs)

      # then start  the intro flow
      case result do
        {:ok, contact} ->
          Flows.start_contact_flow(@dg_glific_flow_id, contact)

        {:error, error} ->
          # log this error and send to appsignal also
          Logger.error(error)
          {_, stacktrace} = Process.info(self(), :current_stacktrace)
          Appsignal.send_error(:error, error, stacktrace)
      end
    end

    # always return 200 and an empty response
    conn |> json("")
  end

  def exotel_optin(conn, _params), do:  conn |> json("")
end
