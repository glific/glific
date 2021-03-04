defmodule Glific.Contacts.Import do
  @moduledoc """
  The Contact Importer Module
  """

  alias Glific.{Contacts, Groups, Settings}

  defp cleanup_contact_data(data, organization_id) do
    %{
      name: data["name"],
      phone: data["phone"],
      organization_id: organization_id,
      language_id: Enum.at(Settings.get_language_by_label_or_locale(data["language"]), 0).id,
      optin_time: elem(Timex.parse(data["opt_in"], "{YYYY}-{0M}-{0D}"), 1)
    }
  end

  defp insert_or_update_contact_data(contact, group_id) do
    {_, contact} = Contacts.create_or_update_contact(contact)

    Groups.create_contact_group(%{
      contact_id: contact.id,
      group_id: group_id,
      organization_id: contact.organization_id
    })
  end

  @doc """
  This method allows importing of contacts to a particular organization and group

  The method takes in a csv file path and adds the contacts to the particular organization
  and group.
  """
  @spec import_contacts(String.t(), integer, integer) :: list()
  def import_contacts(file_path, organization_id, group_id) do
    File.stream!(file_path)
    |> CSV.decode(headers: true, strip_fields: true)
    |> Enum.map(fn {_, data} -> cleanup_contact_data(data, organization_id) end)
    |> Enum.map(fn contact -> insert_or_update_contact_data(contact, group_id) end)

  end
end
