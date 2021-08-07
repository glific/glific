defmodule GlificWeb.ExotelController do
  @moduledoc """
  The controller to process events received from exotel
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.{Contacts, Flows, Partners}

  @doc """
  First implementation of processing optin contact callback from exotel
  for digital green. Will need to make it more generic for broader use case
  across other NGOs

  We use the callto and directon parameters to ensure a valid call from exotel
  """
  @spec optin(Plug.Conn.t(), map) :: Plug.Conn.t()
  def optin(
        %Plug.Conn{assigns: %{organization_id: organization_id}} = conn,
        %{
          "CallFrom" => exotel_from,
          "CallTo" => _exotel_call_to,
          "To" => exotel_to
        } = _params
      ) do
    organization = Partners.organization(organization_id)

    credentials = organization.services["exotel"]

    if is_nil(credentials) do
      log_error("exotel credentials missing")
    else
      keys = credentials.keys

      {phone, ngo_exotel_phone} =
        if keys["direction"] == "incoming",
          do: {exotel_from, exotel_to},
          else: {exotel_to, exotel_from}

      if ngo_exotel_phone == credentials.secrets["phone"] do
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
            {:ok, flow_id} = Glific.parse_maybe_integer(keys["flow_id"])
            Flows.start_contact_flow(flow_id, contact)

          {:error, error} ->
            log_error(error)
        end
      else
        log_error("exotel credentials mismatch")
      end
    end

    # always return 200 and an empty response
    json(conn, "")
  end

  def optin(conn, _params), do: json(conn, "")

  @spec log_error(String.t()) :: any
  defp log_error(message) do
    # log this error and send to appsignal also
    Logger.error(message)
    {_, stacktrace} = Process.info(self(), :current_stacktrace)
    Appsignal.send_error(:error, message, stacktrace)
  end
end
