defmodule Glific.Clients.DigitalGreen.Extension do
  alias Glific.{
    Contacts,
    Groups,
    Groups.Group,
    Repo
  }

  def increment_day(group_name, contact_field_name, increment_value, organization_id) do
    {:ok, group} = Repo.fetch_by(Group, %{label: group_name, organization_id: organization_id})

    contact_ids = Groups.contact_ids(group.id)

    contact_ids
    |> Enum.each(fn contact_id ->
      update_contact_field(contact_id, contact_field_name, increment_value)
    end)
  end

  defp update_contact_field(contact_id, contact_field_name, increment_value) do
    contact = Contacts.get_contact!(contact_id)

    contact_fields =
      if is_nil(contact.fields),
        do: %{},
        else: contact.fields

    value =
      contact_fields[contact_field_name]["value"]
      |> increment(increment_value)

    fields =
      contact_fields
      |> Map.put(contact_field_name, %{
        value: value,
        label: contact_field_name,
        type: contact_fields[contact_field_name]["type"],
        inserted_at: DateTime.utc_now()
      })

    Contacts.update_contact(
      contact,
      %{fields: fields}
    )
  end

  defp increment(value, increment_value) do
    {:ok, value} = Glific.parse_maybe_integer(value)
    value + increment_value
  end

  def swap_groups(first_group, second_group, contact_field_name, sentinel_value, organization_id) do
    {:ok, group1} = Repo.fetch_by(Group, %{label: first_group, organization_id: organization_id})
    {:ok, group2} = Repo.fetch_by(Group, %{label: second_group, organization_id: organization_id})
    move_to_group(group1, group2, contact_field_name, sentinel_value, organization_id)
    remove_from_group(group1, contact_field_name, sentinel_value)
  end

  defp move_to_group(
         first_group,
         second_group,
         contact_field_name,
         sentinel_value,
         organization_id
       ) do
    contact_ids = Groups.contact_ids(first_group.id)

    contact_ids
    |> compute_threshold(contact_field_name, sentinel_value)
    |> Enum.each(fn contact_id ->
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: second_group.id,
        organization_id: organization_id
      })
    end)
  end

  defp remove_from_group(group, contact_field_name, sentinel_value) do
    contact_ids =
      Groups.contact_ids(group.id)
      |> compute_threshold(contact_field_name, sentinel_value)

    Groups.delete_group_contacts_by_ids(group.id, contact_ids)
  end

  def compute_threshold(contact_ids, contact_field_name, sentinel_value) do
    contact_ids
    |> Enum.filter(fn contact_id ->
      fields_map = Contacts.get_contact!(contact_id).fields[contact_field_name]
      fields_map["value"] > sentinel_value
    end)
  end
end
