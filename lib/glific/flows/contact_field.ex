defmodule Glific.Flows.ContactField do
  @moduledoc """
  Since many of the functions set/update fields in contact and related tables, lets
  centralize all the code here for now
  """

  alias Glific.{
    Contacts,
    Contacts.ContactsField,
    Flows.FlowContext,
    Repo
  }

  @doc """
  Add a field {key, value} to a contact. For now, all preferences are stored under the
  settings map, with a sub-map of preferences. We expect to get more clarity on this soon
  """
  @spec add_contact_field(FlowContext.t(), String.t(), String.t(), String.t(), String.t()) ::
          FlowContext.t()
  def add_contact_field(context, field, label, value, type) do
    contact_fields =
      if is_nil(context.contact.fields),
        do: %{},
        else: context.contact.fields

    fields =
      contact_fields
      |> Map.put(field, %{value: value, label: label, type: type, inserted_at: DateTime.utc_now()})

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
  @spec list_contacts_fields(map()) :: [Tag.t()]
  def list_contacts_fields(args),
    do: Repo.list_filter(args, ContactsField, &Repo.opts_with_inserted_at/2, &Repo.filter_with/2)

  @doc """
  Return the count of contacts_fields, using the same filter as list_contacts_fields
  """
  @spec count_contacts_fields(map()) :: integer
  def count_contacts_fields(args),
    do: Repo.count_filter(args, ContactsField, &Repo.filter_with/2)

  @doc """
  Create contact field
  """
  @spec create_contact_field(map()) :: {:ok, ContactsField.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_field(attrs) do
    %ContactsField{}
    |> ContactsField.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a contact field.

  ## Examples

      iex> update_contacts_field(contacts_field, %{field: new_value})
      {:ok, %ContactsField{}}

      iex> update_contacts_field(contacts_field, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_contacts_field(ContactsField.t(), map()) ::
          {:ok, ContactsField.t()} | {:error, Ecto.Changeset.t()}
  def update_contacts_field(%ContactsField{} = contacts_field, attrs) do
    contacts_field
    |> ContactsField.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a contact field.

  ## Examples

      iex> delete_contacts_field(contacts_field)
      {:ok, %ContactsField{}}

      iex> delete_contacts_field(contacts_field)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_contacts_field(ContactsField.t()) ::
          {:ok, ContactsField.t()} | {:error, Ecto.Changeset.t()}
  def delete_contacts_field(%ContactsField{} = contacts_field) do
    contacts_field
    |> ContactsField.changeset(%{})
    |> Repo.delete()
  end
end
