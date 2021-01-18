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
    ApiClient.optin_contact(organization_id, %{user: attrs.phone})
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

    case ApiClient.fetch_opted_in_contacts(attrs.organization_id) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, response_data} = Jason.decode(body)

        if response_data["status"] == "error" do
          {:error, "Error updating opted-in contacts #{response_data["message"]}"}
        else
          users = response_data["users"]
          update_contacts(users, organization)
        end

      {:ok, %Tesla.Env{status: status}} when status in 400..499 ->
        {:error, "Error updating opted-in contacts invalid key"}

      {:error, %Tesla.Error{reason: reason}} ->
        {:error, "Error updating opted-in contacts #{reason}"}
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
