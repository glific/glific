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

  test "add contact fields in bulk",
       %{organization_id: organization_id} = _attrs do
    [contact | _] =
      Contacts.list_contacts(%{
        filter: %{name: "Default receiver", organization_id: organization_id}
      })

    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    entries = [
      %{key: "age_group", label: "Age Group", value: "18-25"},
      %{key: "district", label: "District", value: "Pune"}
    ]

    updated_context = ContactField.add_contact_fields(context, entries)

    {:ok, updated_contact} = Repo.fetch_by(Contacts.Contact, %{id: contact.id})

    assert updated_contact.fields["age_group"]["value"] == "18-25"
    assert updated_contact.fields["age_group"]["label"] == "Age Group"
    assert updated_contact.fields["age_group"]["type"] == "string"
    assert updated_contact.fields["district"]["value"] == "Pune"

    # the contact on the returned context carries the new fields, so the flow can
    # keep writing without a reload
    assert updated_context.contact.fields["age_group"].value == "18-25"

    # a later bulk write merges into, rather than replaces, what is already there
    ContactField.add_contact_fields(updated_context, [
      %{key: "gender", label: "Gender", value: "female"}
    ])

    {:ok, updated_contact} = Repo.fetch_by(Contacts.Contact, %{id: contact.id})
    assert updated_contact.fields["age_group"]["value"] == "18-25"
    assert updated_contact.fields["gender"]["value"] == "female"
  end

  test "add contact fields in bulk keeps the last value of a repeated key",
       %{organization_id: organization_id} = _attrs do
    [contact | _] =
      Contacts.list_contacts(%{
        filter: %{name: "Default receiver", organization_id: organization_id}
      })

    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    ContactField.add_contact_fields(context, [
      %{key: "age_group", label: "Age Group", value: "first"},
      %{key: "age_group", label: "Age Group", value: "last"}
    ])

    {:ok, updated_contact} = Repo.fetch_by(Contacts.Contact, %{id: contact.id})
    assert updated_contact.fields["age_group"]["value"] == "last"

    # and writes a single history row for it
    history =
      Contacts.list_contact_history(%{
        filter: %{contact_id: contact.id, event_type: "contact_fields_updated"}
      })

    assert length(history) == 1
  end

  test "add contact fields in bulk does not relabel an existing field definition",
       %{organization_id: organization_id} = _attrs do
    [contact | _] =
      Contacts.list_contacts(%{
        filter: %{name: "Default receiver", organization_id: organization_id}
      })

    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    {:ok, _} =
      ContactField.create_contact_field(%{
        name: "Age Group",
        shortcode: "age_group",
        organization_id: organization_id,
        scope: :contact
      })

    ContactField.add_contact_fields(context, [
      %{key: "age_group", label: "Renamed Age Group", value: "18-25"}
    ])

    {:ok, definition} =
      Repo.fetch_by(Contacts.ContactsField, %{
        shortcode: "age_group",
        organization_id: organization_id
      })

    assert definition.name == "Age Group"
  end

  test "add contact fields in bulk is a no-op for an empty list",
       %{organization_id: organization_id} = _attrs do
    [contact | _] =
      Contacts.list_contacts(%{
        filter: %{name: "Default receiver", organization_id: organization_id}
      })

    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    assert ContactField.add_contact_fields(context, []).contact.fields == contact.fields
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
