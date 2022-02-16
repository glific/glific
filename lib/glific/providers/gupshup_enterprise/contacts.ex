defmodule Glific.Providers.GupshupEnterpriseContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup Enterprise
  """

  use Publicist

  alias Glific.{
    Contacts.Contact,
    Providers.Contacts,
    Providers.Gupshup.Enterprise.ApiClient
  }

  @behaviour Glific.Providers.ContactBehaviour

  @doc """
    Update a contact phone as opted in
  """
  @impl Glific.Providers.ContactBehaviour

  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, list()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    ApiClient.optin_contact(organization_id, %{"phone_number" => attrs.phone})
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        Contacts.create_or_update_contact(attrs, organization_id)

      _ ->
        {:error, ["gupshup_enterprise", "couldn't connect"]}
    end
  end
end
