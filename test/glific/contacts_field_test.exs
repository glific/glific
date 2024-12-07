defmodule Glific.ContactsFieldTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactsField,
    Fixtures,
    Flows.ContactField,
    Groups.WAGroup,
    Groups.WAGroups,
    Repo
  }

  describe "contacts_field" do
    @valid_attrs %{
      name: "Nationality",
      shortcode: "nationality"
    }
    @valid_more_attrs %{
      name: "Age Category",
      shortcode: "age category"
    }
    @invalid_attrs %{
      name: nil,
      shortcode: nil
    }

    @wa_group_attrs %{
      name: "Nationality",
      shortcode: "nationality",
      scope: :wa_group
    }
  end

  test "count_contacts_fields/1 returns count of all contacts_field",
       %{organization_id: _organization_id} = attrs do
    contacts_field_count = ContactField.count_contacts_fields(%{filter: attrs})

    _contacts_field_1 = Fixtures.contacts_field_fixture(Map.merge(attrs, @valid_attrs))

    assert ContactField.count_contacts_fields(%{filter: attrs}) == contacts_field_count + 1

    _contacts_field_3 = Fixtures.contacts_field_fixture(Map.merge(attrs, @valid_more_attrs))

    assert ContactField.count_contacts_fields(%{filter: attrs}) == contacts_field_count + 2

    assert ContactField.count_contacts_fields(%{
             filter: Map.merge(attrs, %{shortcode: "nationality"})
           }) == 1

    _contacts_field_3 = Fixtures.contacts_field_fixture(Map.merge(attrs, @wa_group_attrs))

    assert ContactField.count_contacts_fields(%{
             filter: Map.merge(attrs, %{shortcode: "nationality"})
           }) == 2

    assert ContactField.count_contacts_fields(%{
             filter: Map.merge(attrs, %{shortcode: "nationality", scope: :contact})
           }) == 1
  end

  test "list_contacts_fields/1 returns all contacts_field",
       %{organization_id: organization_id} = attrs do
    contacts_field = Fixtures.contacts_field_fixture(%{organization_id: organization_id})

    assert Enum.filter(
             ContactField.list_contacts_fields(%{filter: attrs}),
             fn t -> t.name == contacts_field.name end
           ) ==
             [contacts_field]
  end

  test "create_contacts_field/1 with valid data creates a contacts_field", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id, when: DateTime.utc_now()})

    assert {:ok, %ContactsField{} = contacts_field} = ContactField.create_contact_field(attrs)
    assert contacts_field.name == "Nationality"
    assert contacts_field.shortcode == "nationality"
  end

  test "create_contacts_field/1 with invalid data returns error changeset", %{
    organization_id: organization_id
  } do
    attrs =
      Map.merge(@invalid_attrs, %{organization_id: organization_id, when: DateTime.utc_now()})

    assert {:error, %Ecto.Changeset{}} = ContactField.create_contact_field(attrs)
  end

  test "update_contacts_field/2 with valid data updates the contacts_field", %{
    organization_id: organization_id
  } do
    contact =
      Fixtures.contact_fixture()
      |> ContactField.do_add_contact_field("test", "test field", "hello")

    assert contact.fields != %{}

    attrs =
      %{
        name: "Citizen",
        shortcode: "citizen",
        organization_id: organization_id
      }

    contacts_field = ContactsField |> where([cf], cf.shortcode == "test") |> Repo.one()

    assert {:ok, %ContactsField{} = updated_contacts_field} =
             ContactField.update_contacts_field(contacts_field, attrs)

    assert updated_contacts_field.name == "Citizen"
    assert updated_contacts_field.shortcode == "citizen"

    assert %Contact{fields: %{"citizen" => %{"label" => "Citizen"}}} =
             Contacts.get_contact(contact.id)
  end

  test "update_contacts_field/2 with valid data updates the contacts_field when scope is group",
       %{
         organization_id: organization_id
       } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })
      |> ContactField.do_add_wa_group_field("test", "test field", "hello")

    assert wa_group.fields != %{}

    attrs =
      %{
        name: "Citizen",
        shortcode: "citizen",
        organization_id: organization_id
      }

    contacts_field = ContactsField |> where([cf], cf.shortcode == "test") |> Repo.one()

    assert {:ok, %ContactsField{} = updated_contacts_field} =
             ContactField.update_contacts_field(contacts_field, attrs)

    assert updated_contacts_field.name == "Citizen"
    assert updated_contacts_field.shortcode == "citizen"

    assert %WAGroup{fields: %{"citizen" => %{"label" => "Citizen"}}} =
             WAGroups.get_wa_group!(wa_group.id)
  end

  test "contacts_field/1 deletes the contacts_field", %{organization_id: organization_id} do
    contacts_field = Fixtures.contacts_field_fixture(%{organization_id: organization_id})

    assert {:ok, %ContactsField{}} = ContactField.delete_contacts_field(contacts_field)

    assert_raise Ecto.NoResultsError, fn -> Repo.get!(ContactsField, contacts_field.id) end
  end

  test "contacts_field/1 deletes the contacts_field where scope is group", %{
    organization_id: organization_id
  } do
    contacts_field =
      Fixtures.contacts_field_fixture(%{organization_id: organization_id, scope: :wa_group})

    assert {:ok, %ContactsField{}} = ContactField.delete_contacts_field(contacts_field)

    assert_raise Ecto.NoResultsError, fn -> Repo.get!(ContactsField, contacts_field.id) end
  end

  test "delete_associated_contacts_field/2 deletes data associated with contacts_field",
       %{organization_id: organization_id} = _attrs do
    contact =
      Fixtures.contact_fixture()
      |> ContactField.do_add_contact_field("test", "Test Field", "it works")

    [contact_field | _] =
      ContactField.list_contacts_fields(%{
        filter: %{name: "Test Field", shortcode: "test"},
        organization_id: organization_id
      })

    assert get_in(contact.fields, ["test", :value]) == "it works"

    # Deleting the contact field and its associated data
    ContactField.delete_associated_contacts_field(contact_field, organization_id)
    assert Contacts.get_contact(contact.id).fields == %{}
  end

  test "delete_associated_contacts_field/2 deletes data associated with contacts_field where scope is group",
       %{organization_id: organization_id} = _attrs do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })
      |> ContactField.do_add_wa_group_field("test", "Test Field", "it works")

    [contact_field | _] =
      ContactField.list_contacts_fields(%{
        filter: %{name: "Test Field", shortcode: "test"},
        organization_id: organization_id
      })

    assert get_in(wa_group.fields, ["test", :value]) == "it works"

    # Deleting the contact field and its associated data
    ContactField.delete_associated_contacts_field(contact_field, organization_id)
    assert WAGroups.get_wa_group!(wa_group.id).fields == %{}
  end

  test "merge_contacts_fields/2 merge old contact field with new field", attrs do
    contact =
      Fixtures.contact_fixture()
      |> ContactField.do_add_contact_field("old", "Old Field", "hello")
      |> ContactField.do_add_contact_field("new", "New Field", "hello world")

    # Getting the contact field to be replaced
    old_contact_field = ContactsField |> where([cf], cf.shortcode == "old") |> Repo.one()

    assert old_contact_field != nil

    # updating old field values with new field
    attrs = Map.merge(attrs, %{label: "New Field", shortcode: "new"})

    ContactField.merge_contacts_fields(old_contact_field, attrs)

    # checking if the contact variable has been merged
    assert %Contact{fields: %{"new" => %{"value" => "hello world"}}} =
             Contacts.get_contact(contact.id)

    # checking if the old field is removed
    assert Contacts.get_contact(contact.id).fields["old"] == nil
  end

  test "merge_contacts_fields/2 merge old contact field with new field where scope is group",
       attrs do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })
      |> ContactField.do_add_wa_group_field("old", "Old Field", "hello")
      |> ContactField.do_add_wa_group_field("new", "New Field", "hello world")

    # Getting the contact field to be replaced
    old_contact_field = ContactsField |> where([cf], cf.shortcode == "old") |> Repo.one()

    assert old_contact_field != nil

    # updating old field values with new field
    attrs = Map.merge(attrs, %{label: "New Field", shortcode: "new"})

    ContactField.merge_contacts_fields(old_contact_field, attrs)

    # checking if the contact variable has been merged
    assert %WAGroup{fields: %{"new" => %{"value" => "hello world"}}} =
             WAGroups.get_wa_group!(wa_group.id)

    # checking if the old field is removed
    assert WAGroups.get_wa_group!(wa_group.id).fields["old"] == nil
  end
end
