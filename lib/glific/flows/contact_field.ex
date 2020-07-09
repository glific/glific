defmodule Glific.Flows.ContactField do
  @moduledoc """
  Since many of the functions set/update fields in contact and related tables, lets
  centralize all the code here for now
  """

  alias Glific.{
    Contacts,
    Flows.Context
  }

  @doc """
  Add a field {key, value} to a contact. For now, all preferences are stored under the
  settings map, with a sub-map of preferences. We expect to get more clarity on this soon
  """
  @spec add_contact_field(Context.t(), String.t(), String.t(), String.t()) :: Context.t()
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
  @spec reset_contact_fields(Context.t()) :: Context.t()
  def reset_contact_fields(context) do
    {:ok, contact} =
      Contacts.update_contact(
        context.contact,
        %{fields: %{}}
      )

    Map.put(context, :contact, contact)
  end
end
