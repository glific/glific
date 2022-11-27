defmodule Glific.Providers.GupshupEnterpriseContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup Enterprise
  """

  use Publicist

  @behaviour Glific.Providers.ContactBehaviour

  alias Glific.{
    Contacts,
    Providers.Gupshup.Enterprise.ApiClient
  }

  @doc """
    Update a contact phone as opted in
  """
  @impl Glific.Providers.ContactBehaviour

  @spec optin_contact(map()) ::
          {:ok, Contacts.Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, list()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    ApiClient.optin_contact(organization_id, %{"phone_number" => attrs.phone})
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        Contacts.contact_opted_in(
          attrs,
          organization_id,
          attrs[:optin_time] || DateTime.utc_now(),
          method: attrs[:method] || "BSP"
        )

      _ ->
        {:error, ["gupshup_enterprise", "couldn't connect"]}
    end
  end

  @doc """
  Fetch opted in contacts data from providers server
  """
  @impl Glific.Providers.ContactBehaviour
  @spec fetch_opted_in_contacts(map()) :: :ok | {:error, String.t()}
  def fetch_opted_in_contacts(_attrs), do: :ok
end
