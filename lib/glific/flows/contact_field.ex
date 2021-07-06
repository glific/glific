defmodule Glific.Flows.ContactField do
  @moduledoc """
  Since many of the functions set/update fields in contact and related tables, lets
  centralize all the code here for now
  """

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactsField,
    Flows.FlowContext,
    Flows.MessageVarParser,
    Repo
  }

  @doc """
  Add a field {key, value} to a contact. For now, all preferences are stored under the
  settings map, with a sub-map of preferences. We expect to get more clarity on this soon
  """
  @spec add_contact_field(FlowContext.t(), String.t(), String.t(), String.t(), String.t()) ::
          FlowContext.t()
  def add_contact_field(context, field, label, value, type) do
    contact = do_add_contact_field(context.contact, field, label, value, type)

    Map.put(context, :contact, contact)
  end

  @doc """
  Add contact field taking contact as parameter
  """
  @spec do_add_contact_field(Contact.t(), String.t(), String.t(), any(), String.t()) ::
          Contact.t()
  def do_add_contact_field(contact, field, label, value, type) do
    contact_fields =
      if is_nil(contact.fields),
        do: %{},
        else: contact.fields

    fields =
      contact_fields
      |> Map.put(field, %{value: value, label: label, type: type, inserted_at: DateTime.utc_now()})

    {:ok, contact} =
      Contacts.update_contact(
        contact,
        %{fields: fields}
      )

    contact
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
    parse contact fields values with check if it has
  """
  @spec parse_contact_field_value(FlowContext.t(), String.t()) :: String.t()
  def parse_contact_field_value(context, value) do
    message_vars = %{
      "results" => context.results,
      "contact" => Contacts.get_contact_field_map(context.contact_id),
      "flow" => %{name: context.flow.name, id: context.flow.id}
    }

    value
    |> MessageVarParser.parse(message_vars)
    |> Glific.execute_eex()
  end

  @doc """
  list contacts fields.
  """
  @spec list_contacts_fields(map()) :: [ContactsField.t()]
  def list_contacts_fields(args) do
    Repo.list_filter(args, ContactsField, &Repo.opts_with_inserted_at/2, &Repo.filter_with/2)
    |> Enum.map(fn contacts_field ->
      add_variable_field(contacts_field)
    end)
  end

  @spec add_variable_field(ContactsField.t()) :: map()
  defp add_variable_field(contacts_field) do
    contacts_field
    |> Map.put(:variable, "@contact.fields.#{contacts_field.shortcode}")
  end

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
    with {:ok, contacts_field} <-
           %ContactsField{}
           |> ContactsField.changeset(attrs)
           |> Repo.insert() do
      contacts_field = add_variable_field(contacts_field)
      {:ok, contacts_field}
    end
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
