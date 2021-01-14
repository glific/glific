defmodule Glific.Providers.GupshupContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup
  """

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient
  }

  @behaviour Glific.Providers.ContactBehaviour

  @doc """
    Update a contact phone as opted in
  """
  @impl Glific.Providers.ContactBehaviour

  @spec optin_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    organization = Partners.organization(organization_id)
    bsp_credentials = organization.services["bsp"]

    url =
      bsp_credentials.keys["api_end_point"] <>
        "/app/opt/in/" <> bsp_credentials.secrets["app_name"]

    api_key = bsp_credentials.secrets["api_key"]

    ApiClient.post(url, %{user: attrs.phone}, headers: [{"apikey", api_key}])
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        %{
          name: attrs[:name],
          phone: attrs.phone,
          organization_id: organization_id,
          optin_time: DateTime.utc_now(),
          bsp_status: :hsm
        }
        |> Contacts.create_contact()

      _ ->
        {:error, ["gupshup", "couldn't connect"]}
    end
  end

  @doc """
  Fetch opted in contacts data from providers server
  """
  @spec fetch_opted_in_contacts(map()) :: :ok | any()
  def fetch_opted_in_contacts(attrs) do
    organization = Partners.organization(attrs.organization_id)
    url = attrs.keys["api_end_point"] <> "/users/" <> attrs.secrets["app_name"]

    api_key = attrs.secrets["api_key"]

    case ApiClient.get(url, headers: [{"apikey", api_key}]) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, response_data} = Jason.decode(body)
        if is_nil(response_data["users"]) do
          raise "Error updating opted-in contacts #{response_data["message"]}"
        else
          users = response_data["users"]
          update_contacts(users, organization)
        end
      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        raise "Error updating opted-in contacts #{body}"

      {:error, %Tesla.Error{reason: reason}} ->
        raise "Error updating opted-in contacts #{reason}"
    end

    :ok
  end

  @spec update_contacts(list() | nil, Organization.t() | nil) :: :ok | any()
  defp update_contacts(users, organization) do
    Enum.each(users, fn user ->
      # handle scenario when contact has not sent a message yet
      last_message_at =
        if user["lastMessageTimeStamp"] != 0,
          do:
            DateTime.from_unix(user["lastMessageTimeStamp"], :millisecond)
            |> elem(1)
            |> DateTime.truncate(:second),
          else: nil

      {:ok, optin_time} = DateTime.from_unix(user["optinTimeStamp"], :millisecond)

      phone = user["countryCode"] <> user["phoneCode"]

      Contacts.upsert(%{
        phone: phone,
        last_message_at: last_message_at,
        optin_time: optin_time |> DateTime.truncate(:second),
        bsp_status: check_bsp_status(last_message_at),
        organization_id: organization.id,
        language_id: organization.default_language_id
      })
    end)
  end

  @spec check_bsp_status(DateTime.t()) :: atom()
  defp check_bsp_status(last_message_at) do
    if Timex.diff(DateTime.utc_now(), last_message_at, :hours) < 24 do
      :session_and_hsm
    else
      :hsm
    end
  end
end
