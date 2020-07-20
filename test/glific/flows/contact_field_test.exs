defmodule Glific.Flows.ContactFieldTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Flows.ContactField,
    Flows.FlowContext
  }

  setup do
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_contacts()
    :ok
  end

  test "add contact field" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    field = "test field"
    value = "test value"
    type = "string"
    ContactField.add_contact_field(context, field, value, type)

    {:ok, updated_contact} = Repo.fetch_by(Contacts.Contact, %{id: contact.id})
    assert updated_contact.fields[field]["value"] == value
    assert updated_contact.fields[field]["type"] == type
  end

  test "reset contact fields" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    field = "test field"
    value = "test value"
    type = "string"
    ContactField.add_contact_field(context, field, value, type)
    ContactField.reset_contact_fields(context)

    {:ok, updated_contact} = Repo.fetch_by(Contacts.Contact, %{id: contact.id})
    assert updated_contact.fields == %{}
  end
end
