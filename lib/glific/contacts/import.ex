defmodule Glific.Contacts.Import do
    alias Glific.{Contacts, Partners, Groups}

    def import_contact({_, [name,mobile,opt_in,language_id]}) do
        Contacts.create_contact(%{
            name: name,
            phone: mobile,
            organization_id: 1,
            language_id: String.to_integer(language_id),
            optin_time: opt_in
          })
    end

    def import_contacts(file_path, organization_id, group_id) do
        organization = Partners.organization(organization_id)
        group = Groups.get_group!(group_id)

        File.stream!(file_path)
        |> CSV.decode
        |> Enum.map(&import_contact/1)

    end
end

# alias Glific.Contacts.Import
# Import.import_contacts("/Users/mmalhotra/apps/glific/lib/glific/contacts/test.csv", 1, 1)