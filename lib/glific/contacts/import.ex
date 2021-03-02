defmodule Glific.Contacts.Import do
  alias Glific.{Contacts, Groups, Settings}

  @doc """
  This method allows importing of contacts to a particular organization and group

  The method takes in a csv file path and adds the contacts to the particular organization
  and group.
  """
  def import_contacts(file_path, organization_id, group_id) do
    File.stream!(file_path)
    |> CSV.decode(headers: true, strip_fields: true)
    |> Enum.map(fn {_, contact} ->
      %{
        name: contact["name"],
        phone: contact["phone"],
        organization_id: organization_id,
        language_id: Enum.at(Settings.get_language_by_label_or_locale(contact["language"]), 0).id,
        optin_time: elem(Timex.parse(contact["opt_in"], "{YYYY}-{0M}-{0D}"), 1)
      }
    end)
    |> Enum.map(fn contact ->
      Contacts.create_or_update_contact(%{
        name: contact.name,
        phone: contact.phone,
        organization_id: organization_id,
        language_id: contact.language_id,
        optin_time: contact.optin_time
      })
    end)
    |> Enum.reduce(
      [],
      fn {_, contact}, acc ->
        [
          %{contact_id: contact.id, group_id: group_id, organization_id: organization_id}
          | acc
        ]
      end
    )
    |> Enum.map(&Groups.create_contact_group/1)

    :ok
  end
end
