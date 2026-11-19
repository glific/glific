defmodule GlificWeb.ExotelController do
  @moduledoc """
  The controller to process events received from exotel
  """

  use GlificWeb, :controller

  alias Glific.{Contacts, Flows, Partners, Repo, SafeLog}
  alias Glific.Providers.Exotel.Instrumentation

  defmodule Error do
    @moduledoc """
    Raised when an Exotel opt-in callback cannot be processed. NGOs cannot act on these
    failures themselves, so they are reported to AppSignal. The low-cardinality `:message`
    groups incidents; `:organization_id` and `:reason` carry per-occurrence context.
    """
    defexception [:message, :reason, :organization_id]
  end

  @optin_params ["CallFrom", "CallTo", "To"]
  @appsignal_namespace "exotel"

  @doc """
  First implementation of processing optin contact callback from exotel
  for digital green. Will need to make it more generic for broader use case
  across other NGOs

  We use the callto and directon parameters to ensure a valid call from exotel
  """
  @spec optin(Plug.Conn.t(), map) :: Plug.Conn.t()
  def optin(%Plug.Conn{assigns: %{organization_id: organization_id}} = conn, params) do
    case missing_optin_params(params) do
      [] ->
        process_optin(organization_id, params)

      missing ->
        report_failure(
          "Exotel optin request missing expected params",
          organization_id,
          "missing: #{param_names(missing)}, received: #{param_names(Map.keys(params))}"
        )
    end

    # always return 200 and an empty response
    json(conn, "")
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
      do: report_failure("Exotel credentials missing", organization_id),
      else: optin_contact(organization_id, credentials, params)
  end

  @spec optin_contact(non_neg_integer(), map(), map()) :: :ok
  defp optin_contact(organization_id, credentials, params) do
    {phone, ngo_exotel_phone} = call_phones(credentials.keys, params)

    case Map.fetch(get_phone_flow_map(credentials), ngo_exotel_phone) do
      {:ok, flow_to_start} ->
        start_optin_flow(organization_id, phone, flow_to_start)

      :error ->
        report_failure(
          "Exotel credentials mismatch",
          organization_id,
          "no flow configured for the exotel phone in this call"
        )
    end
  end

  # Phones stay `term()`: a bracketed query param (`?CallFrom[]=a`) reaches here as a
  # list, which `clean_phone/1` passes through untouched.
  @spec call_phones(map(), map()) :: {term(), term()}
  defp call_phones(%{"direction" => "incoming"}, %{"CallFrom" => from, "To" => to}),
    do: {from, to}

  defp call_phones(_keys, %{"CallFrom" => from, "To" => to}), do: {to, from}

  @spec start_optin_flow(non_neg_integer(), term(), String.t()) :: :ok
  defp start_optin_flow(organization_id, phone, flow_to_start) do
    attrs = %{
      phone: clean_phone(phone),
      method: "Exotel",
      organization_id: organization_id
    }

    case Contacts.optin_contact(attrs) do
      {:ok, contact} ->
        {:ok, flow_id} = Glific.parse_maybe_integer(flow_to_start)
        Flows.start_contact_flow(flow_id, contact)
        Instrumentation.track_action("optin", :success, organization_id)

      {:error, error} ->
        report_failure(
          "Exotel optin contact failed",
          organization_id,
          SafeLog.safe_inspect(error)
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

  @spec report_failure(String.t(), non_neg_integer(), String.t() | nil) :: :ok
  defp report_failure(message, organization_id, reason \\ nil) do
    Instrumentation.track_action("optin", :failure, organization_id)

    Glific.log_exception(
      %Error{message: message, reason: reason, organization_id: organization_id},
      namespace: @appsignal_namespace,
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
