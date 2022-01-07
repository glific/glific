defmodule Glific.BSPContacts.Contact do
  @moduledoc """
  The minimal wrapper for the base Contact structure
  """
  alias Glific.{
    Contacts,
    Contacts.Contact,
    Repo
  }

  @doc """
  This method creates a contact if it does not exist. Otherwise, updates it.
  """
  @spec create_or_update_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_or_update_contact(contact_data) do
    case Repo.get_by(Contact, %{phone: contact_data.phone}) do
      nil ->
        Contacts.create_contact(contact_data)

      contact ->
        # in the case of update we need to ensure that we preserve bsp_status
        # and optin_time, method if the contact is already opted in
        contact_data =
          if contact.optin_status,
            do:
              contact_data
              |> Map.put(:bsp_status, contact.bsp_status || contact_data.bsp_status)
              |> Map.put(:optin_method, contact.optin_method || contact_data.optin_method)
              |> Map.put(:optin_time, contact.optin_time || contact_data.optin_time),
            else: contact_data

        Contacts.update_contact(contact, contact_data)
    end
  end
end
