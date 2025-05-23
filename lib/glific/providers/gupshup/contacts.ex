defmodule Glific.Providers.GupshupContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup
  """

  use Publicist

  @behaviour Glific.Providers.ContactBehaviour

  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{
    Contacts,
    Contacts.Contact
  }

  @doc """
    Update a contact phone as opted in
  """

  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, list()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    Contacts.contact_opted_in(
      attrs,
      organization_id,
      attrs[:optin_time] || DateTime.utc_now(),
      method: attrs[:method] || "BSP"
    )
  end
end
