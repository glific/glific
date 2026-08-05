defmodule GlificWeb.ExotelController do
  @moduledoc """
  The controller to process events received from exotel
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.{Contacts, Flows, Partners, Repo, SafeLog}

  defmodule Error do
    @moduledoc """
    Raised when an Exotel opt-in callback cannot be processed. NGOs cannot act on these
    failures themselves, so they are reported to AppSignal. The low-cardinality `:message`
    groups incidents; `:organization_id` and `:reason` carry per-occurrence context.
    """
    defexception [:message, :reason, :organization_id]
  end

  @optin_params ["CallFrom", "CallTo", "To"]
  @appsignal_group "exotel"

  @doc """
  First implementation of processing optin contact callback from exotel
  for digital green. Will need to make it more generic for broader use case
  across other NGOs

  We use the callto and directon parameters to ensure a valid call from exotel
  """
  @spec optin(Plug.Conn.t(), map) :: Plug.Conn.t()
  def optin(%Plug.Conn{assigns: %{organization_id: organization_id}} = conn, params) do
    log_callback(organization_id, params)

    case missing_optin_params(params) do
      [] ->
        process_optin(organization_id, params)

      missing ->
        log_error(
          "Exotel optin request missing expected params",
          organization_id,
          "missing: #{param_names(missing)}, received: #{param_names(Map.keys(params))}"
        )
    end

    # always return 200 and an empty response
    json(conn, "")
  end

  def optin(conn, params) do
    log_error(
      "Exotel optin request received without an organization",
      nil,
      "received: #{param_names(Map.keys(params))}"
    )

    json(conn, "")
  end

  @spec log_callback(non_neg_integer(), map()) :: :ok
  defp log_callback(organization_id, params) do
    message = "exotel optin callback: #{SafeLog.safe_inspect(params)}"
    Logger.info(message)
    Appsignal.Logger.info(@appsignal_group, message, %{organization_id: organization_id})
  end

  @spec missing_optin_params(map()) :: [String.t()]
  defp missing_optin_params(params),
    do: Enum.filter(@optin_params, &blank?(Map.get(params, &1)))

  @spec blank?(term()) :: boolean()
  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  @spec process_optin(non_neg_integer(), map()) :: any()
  defp process_optin(organization_id, params) do
    organization = Partners.organization(organization_id)
    Repo.put_process_state(organization.id)
    credentials = organization.services["exotel"]

    if is_nil(credentials),
      do: log_error("Exotel credentials missing", organization_id),
      else: optin_contact(organization_id, credentials, params)
  end

  @spec optin_contact(non_neg_integer(), map(), map()) :: any()
  defp optin_contact(organization_id, credentials, %{
         "CallFrom" => exotel_from,
         "To" => exotel_to
       }) do
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

      # then start  the intro flow
      case Contacts.optin_contact(attrs) do
        {:ok, contact} ->
          flow_to_start = phone_flow_map[ngo_exotel_phone]
          {:ok, flow_id} = Glific.parse_maybe_integer(flow_to_start)
          Flows.start_contact_flow(flow_id, contact)

        {:error, error} ->
          log_error("Exotel optin contact failed", organization_id, SafeLog.safe_inspect(error))
      end
    else
      log_error(
        "Exotel credentials mismatch",
        organization_id,
        "no flow configured for the exotel phone in this call"
      )
    end
  end

  # this will be an issue when we expand beyond India
  @country_code "91"

  @spec clean_phone(String.t()) :: String.t()
  defp clean_phone(phone) when is_binary(phone),
    do: @country_code <> String.slice(phone, -10, 10)

  defp clean_phone(phone), do: phone

  @spec param_names([String.t()]) :: String.t()
  defp param_names([]), do: "none"
  defp param_names(names), do: Enum.join(names, ", ")

  @spec log_error(String.t(), non_neg_integer() | nil, String.t() | nil) :: :ok
  defp log_error(message, organization_id, reason \\ nil) do
    Glific.log_exception(
      %Error{message: message, reason: reason, organization_id: organization_id},
      namespace: @appsignal_group,
      tags: %{organization_id: organization_id, reason: reason}
    )
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
