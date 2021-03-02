defmodule Glific.Contacts.Import do
    alias Glific.{Contacts, Groups}

    @doc """
    This method allows importing of contacts to a particular organization and group

    The method takes in a csv file path and adds the contacts to the particular organization
    and group.
    """
    def import_contacts(file_path, organization_id, group_id) do
        group = Groups.get_group!(group_id)

        File.stream!(file_path)
        |> CSV.decode
        |> Enum.map(fn {_, [name,mobile,opt_in,language_id]} -> Contacts.create_or_update_contact(%{
            name: name,
            phone: mobile,
            organization_id: organization_id,
            language_id: String.to_integer(language_id),
            optin_time: opt_in
          }) end)
        |> Enum.reduce(
            [],
            fn {_,contact}, acc ->
              [
                %{contact_id: contact.id, group_id: group.id, organization_id: organization_id}
                | acc
              ]
            end
          )
        |> Enum.map(&Groups.create_contact_group/1)
    end
end