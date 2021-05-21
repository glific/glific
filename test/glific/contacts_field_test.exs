defmodule Glific.ContactsFieldTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Contacts.ContactsField,
    Fixtures,
    Flows.ContactField,
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
    @update_attrs %{
      name: "Citizen"
    }
    @invalid_attrs %{
      name: nil,
      shortcode: nil
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
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

    assert {:ok, %ContactsField{} = contacts_field} = ContactField.create_contact_field(attrs)

    attrs = Map.merge(@update_attrs, %{shortcode: "citizen"})

    assert {:ok, %ContactsField{} = updated_contacts_field} =
             ContactField.update_contacts_field(contacts_field, attrs)

    assert updated_contacts_field.name == "Citizen"
    assert updated_contacts_field.shortcode == "citizen"
  end

  test "contacts_field/1 deletes the contacts_field", %{organization_id: organization_id} do
    contacts_field = Fixtures.contacts_field_fixture(%{organization_id: organization_id})

    assert {:ok, %ContactsField{}} = ContactField.delete_contacts_field(contacts_field)

    assert_raise Ecto.NoResultsError, fn -> Repo.get!(ContactsField, contacts_field.id) end
  end
end
