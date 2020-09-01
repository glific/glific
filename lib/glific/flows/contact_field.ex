defmodule Glific.Flows.ContactField do
  @moduledoc """
  Since many of the functions set/update fields in contact and related tables, lets
  centralize all the code here for now
  """

  alias Glific.{
    Contacts,
    Contacts.ContactsFields,
    Flows.FlowContext,
    Repo
  }

  @doc """
  Add a field {key, value} to a contact. For now, all preferences are stored under the
  settings map, with a sub-map of preferences. We expect to get more clarity on this soon
  """
  @spec add_contact_field(FlowContext.t(), String.t(), String.t(), String.t()) :: FlowContext.t()
  def add_contact_field(context, field, value, type) do
    contact_fields =
      if is_nil(context.contact.fields),
        do: %{},
        else: context.contact.fields

    fields =
      contact_fields
      |> Map.put(field, %{value: value, type: type, inserted_at: DateTime.utc_now()})

    {:ok, contact} =
      Contacts.update_contact(
        context.contact,
        %{fields: fields}
      )

    Map.put(context, :contact, contact)
  end

  @doc """
  Reset the fields for a contact.
  """
  @spec reset_contact_fields(FlowContext.t()) :: FlowContext.t()
  def reset_contact_fields(context) do
    {:ok, contact} =
      Contacts.update_contact(
        context.contact,
        %{fields: %{}}
      )

    Map.put(context, :contact, contact)
  end


  @doc """
  list contacts fields.
  """
  @spec list_contacts_fields(map()) :: [ContactsFields.t()]
  def list_contacts_fields(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.list_filter(args, ContactsFields, &Repo.opts_with_label/2, &Repo.filter_with/2)


  @doc """
  Create contact field
  """
  @spec create_contact_field(map()) :: {:ok, ContactsFields.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_field(%{organization_id: _organization_id} = attrs) do
    %ContactsFields{}
    |> ContactsFields.changeset(attrs)
    |> Repo.insert()
  end

end
