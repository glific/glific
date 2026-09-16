defmodule Glific.Flows.ContactFieldTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Fixtures,
    Flows.ContactField,
    Flows.FlowContext,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    :ok
  end

  test "add contact field",
       %{organization_id: organization_id} = _attrs do
    [contact | _] =
      Contacts.list_contacts(%{
        filter: %{
          name: "Default receiver",
          organization_id: organization_id
        }
      })

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    field = "test field"
    label = "Test Field"
    value = "test value"
    type = "string"
    ContactField.add_contact_field(context, field, label, value, type)

    {:ok, updated_contact} = Repo.fetch_by(Contacts.Contact, %{id: contact.id})
    assert updated_contact.fields[field]["value"] == value
    assert updated_contact.fields[field]["type"] == type
    assert updated_contact.fields[field]["label"] == label
  end

  test "reset contact fields",
       %{organization_id: organization_id} = _attrs do
    [contact | _] =
      Contacts.list_contacts(%{
        filter: %{
          name: "Default receiver",
          organization_id: organization_id
        }
      })

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    field = "test field"
    value = "test value"
    type = "string"
    label = "Test Field"
    context = ContactField.add_contact_field(context, field, label, value, type)
    _ = ContactField.reset_contact_fields(context)

    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.fields == %{}
  end

  # Deliberately driven from a real persisted FlowContext rather than by passing a channel into
  # `capture_history/3`: the failure this guards against is the plumbing being absent, in which
  # case the `'whatsapp'` column default produces a perfectly valid-looking row and a test that
  # supplied the value itself would still pass.
  for channel <- [:web, :whatsapp] do
    test "a flow event raised in a #{channel} context is recorded on that channel" do
      context = Fixtures.flow_context_fixture(%{channel: unquote(channel)})

      _ = ContactField.reset_contact_fields(context)

      assert [%{channel: unquote(channel), event_type: "contact_fields_reset"}] =
               Contacts.list_contact_history(%{filter: %{contact_id: context.contact_id}})
    end

    test "a contact field set in a #{channel} context is recorded on that channel" do
      context = Fixtures.flow_context_fixture(%{channel: unquote(channel)})

      _ = ContactField.add_contact_field(context, "age", "Age", "22", "string")

      assert [%{channel: unquote(channel), event_type: "contact_fields_updated"}] =
               Contacts.list_contact_history(%{filter: %{contact_id: context.contact_id}})
    end
  end
end
