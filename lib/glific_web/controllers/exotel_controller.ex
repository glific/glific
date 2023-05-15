defmodule GlificWeb.ExotelController do
  @moduledoc """
  The controller to process events received from exotel
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.{Contacts, Flows, Partners, Repo}

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
        } = params
      ) do
    Logger.info("exotel #{inspect(params)}")

    organization = Partners.organization(organization_id)
    Repo.put_process_state(organization.id)
    credentials = organization.services["exotel"]

    if is_nil(credentials) do
      log_error("exotel credentials missing")
    else
      keys = credentials.keys

      {phone, ngo_exotel_phone} =
        if keys["direction"] == "incoming",
          do: {exotel_from, exotel_to},
          else: {exotel_to, exotel_from}

      phone_flow_map = get_phone_flow_map(credentials)

      if Map.has_key?(phone_flow_map, ngo_exotel_phone) do
        # first create and optin the contact
        attrs = %{
          phone: clean_phone(phone),
          method: "Exotel",
          organization_id: organization_id
        }

        result = Contacts.optin_contact(attrs)

        # then start  the intro flow
        case result do
          {:ok, contact} ->
            flow_to_start = phone_flow_map[ngo_exotel_phone]
            {:ok, flow_id} = Glific.parse_maybe_integer(flow_to_start)
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

  def optin(conn, params) do
    Logger.info("exotel unhandled #{inspect(params)}")
    json(conn, "")
  end

  # this will be an issue when we expand beyond India
  @country_code "91"

  @spec clean_phone(String.t()) :: String.t()
  defp clean_phone(phone) when is_binary(phone),
    do: @country_code <> String.slice(phone, -10, 10)

  defp clean_phone(phone), do: phone

  @spec log_error(String.t()) :: any
  defp log_error(message) do
    # log this error and send to appsignal also
    Logger.error(message)
    {_, stacktrace} = Process.info(self(), :current_stacktrace)
    Appsignal.send_error(:error, message, stacktrace)
  end

  @spec get_phone_flow_map(any) :: map()
  defp get_phone_flow_map(credentials) do
    # at some point we should also ensure that phone list and flows list
    # have the same number of entries. Leaving it as a future exercise
    phone_list = credentials.secrets["phone"] |> get_clean_list()
    flows_list = credentials.keys["flow_id"] |> get_clean_list()
    Enum.zip(phone_list, flows_list) |> Enum.into(%{})
  end

  @spec get_clean_list(String.t()) :: [String.t()]
  defp get_clean_list(data) do
    data |> String.replace(" ", "") |> String.split(",")
  end
end
