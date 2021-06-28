defmodule Glific.Clients.DigitalGreen do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Groups,
    Groups.Group,
    Repo
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("daily", fields) do
    update_contact_field_value(
      fields["contact_id"],
      fields["contact_field_name"],
      fields["increment_value"]
    )

    swap_groups(
      fields["stage_one_group_name"],
      fields["stage_two_group_name"],
      fields["contact_field_name"],
      fields["stage_one_upper_limit"],
      fields["organization_id"],
      fields["contact_id"]
    )

    swap_groups(
      fields["stage_two_group_name"],
      fields["stage_three_group_name"],
      fields["contact_field_name"],
      fields["stage_two_upper_limit"],
      fields["organization_id"],
      fields["contact_id"]
    )

    swap_groups(
      fields["stage_three_group_name"],
      nil,
      fields["contact_field_name"],
      fields["stage_two_upper_limit"],
      fields["organization_id"],
      fields["contact_id"]
    )

    fields
  end

  def webhook(_, _fields),
    do: %{}

  @doc """
  Update contact field with updated value
  """
  @spec update_contact_field_value(String.t(), String.t(), non_neg_integer()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def update_contact_field_value(id, contact_field_name, increment_value) do
    {:ok, contact_id} = Glific.parse_maybe_integer(id)
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

  @spec increment(non_neg_integer() | String.t(), non_neg_integer()) :: non_neg_integer()
  defp increment(value, increment_value) do
    {:ok, value} = Glific.parse_maybe_integer(value)
    value + increment_value
  end

  @doc """
  Swap contacts from collection based on sentinal value
  """
  @spec swap_groups(
          String.t(),
          String.t() | nil,
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          map()
        ) ::
          :ok
  def swap_groups(
        first_group_name,
        nil,
        contact_field_name,
        sentinel_value,
        organization_id,
        contact_id
      ) do
    with {:ok, group} <-
           Repo.fetch_by(Group, %{label: first_group_name, organization_id: organization_id}),
         {:ok, contact_id} <- Glific.parse_maybe_integer(contact_id) do
      filtered_id = [contact_id] |> compute_threshold(contact_field_name, sentinel_value)

      Groups.delete_group_contacts_by_ids(group.id, filtered_id)
    end
  end

  def swap_groups(
        first_group_name,
        second_group_name,
        contact_field_name,
        sentinel_value,
        organization_id,
        _contact_id
      ) do
    with {:ok, group1} <-
           Repo.fetch_by(Group, %{label: first_group_name, organization_id: organization_id}),
         {:ok, group2} =
           Repo.fetch_by(Group, %{label: second_group_name, organization_id: organization_id}) do
      move_to_group(group1, group2, contact_field_name, sentinel_value, organization_id)
      remove_from_group(group1, contact_field_name, sentinel_value)
      :ok
    end
  end

  # adding contact to a group
  @spec move_to_group(Group.t(), Group.t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          :ok
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

  # removing contact from a group
  @spec remove_from_group(Group.t(), String.t(), non_neg_integer()) :: {integer(), nil | [term()]}
  defp remove_from_group(group, contact_field_name, sentinel_value) do
    contact_ids =
      Groups.contact_ids(group.id)
      |> compute_threshold(contact_field_name, sentinel_value)

    Groups.delete_group_contacts_by_ids(group.id, contact_ids)
  end

  @doc """
  return list of contact_ids that matches the filter criteria
  """
  @spec compute_threshold(list(), String.t(), non_neg_integer()) :: list()
  def compute_threshold(contact_ids, contact_field_name, sentinel_value) do
    {:ok, sentinel_value} = Glific.parse_maybe_integer(sentinel_value)

    contact_ids
    |> Enum.filter(fn contact_id ->
      fields_map = Contacts.get_contact!(contact_id).fields[contact_field_name]
      fields_map["value"] > sentinel_value
    end)
  end
end
