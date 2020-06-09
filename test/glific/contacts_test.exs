defmodule Glific.ContactsTest do
  use Glific.DataCase, async: true
  alias Glific.Contacts

  describe "contacts" do
    alias Glific.Contacts.Contact

    @valid_attrs %{
      name: "some name",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "some phone",
      status: :valid,
      provider_status: :invalid
    }
    @valid_attrs_1 %{
      name: "some name 1",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "some phone 1",
      status: :invalid,
      provider_status: :invalid
    }
    @valid_attrs_2 %{
      name: "some name 2",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "some phone 2",
      status: :valid,
      provider_status: :valid
    }
    @valid_attrs_3 %{
      name: "some name 3",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "some phone 3",
      status: :invalid,
      provider_status: :valid
    }
    @update_attrs %{
      name: "some updated name",
      optin_time: ~U[2011-05-18 15:01:01Z],
      optout_time: ~U[2011-05-18 15:01:01Z],
      phone: "some updated phone",
      status: :invalid,
      provider_status: :invalid
    }
    @invalid_attrs %{
      name: nil,
      optin_time: nil,
      optout_time: nil,
      phone: nil,
      status: nil,
      provider_status: nil
    }

    def contact_fixture(attrs \\ %{}) do
      {:ok, contact} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Contacts.create_contact()

      contact
    end

    test "list_contacts/0 returns all contacts" do
      contact = contact_fixture()
      assert Contacts.list_contacts() == [contact]
    end

    test "get_contact!/1 returns the contact with given id" do
      contact = contact_fixture()
      assert Contacts.get_contact!(contact.id) == contact
    end

    test "create_contact/1 with valid data creates a contact" do
      assert {:ok, %Contact{} = contact} = Contacts.create_contact(@valid_attrs)
      assert contact.name == "some name"
      assert contact.optin_time == ~U[2010-04-17 14:00:00Z]
      assert contact.optout_time == ~U[2010-04-17 14:00:00Z]
      assert contact.phone == "some phone"
      assert contact.status == :valid
      assert contact.provider_status == :invalid
    end

    test "create_contact/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Contacts.create_contact(@invalid_attrs)
    end

    test "update_contact/2 with valid data updates the contact" do
      contact = contact_fixture()
      assert {:ok, %Contact{} = contact} = Contacts.update_contact(contact, @update_attrs)
      assert contact.name == "some updated name"
      assert contact.optin_time == ~U[2011-05-18 15:01:01Z]
      assert contact.optout_time == ~U[2011-05-18 15:01:01Z]
      assert contact.phone == "some updated phone"
      assert contact.status == :invalid
      assert contact.provider_status == :invalid
    end

    test "update_contact/2 with invalid data returns error changeset" do
      contact = contact_fixture()
      assert {:error, %Ecto.Changeset{}} = Contacts.update_contact(contact, @invalid_attrs)
      assert contact == Contacts.get_contact!(contact.id)
    end

    test "delete_contact/1 deletes the contact" do
      contact = contact_fixture()
      assert {:ok, %Contact{}} = Contacts.delete_contact(contact)
      assert_raise Ecto.NoResultsError, fn -> Contacts.get_contact!(contact.id) end
    end

    test "change_contact/1 returns a contact changeset" do
      contact = contact_fixture()
      assert %Ecto.Changeset{} = Contacts.change_contact(contact)
    end

    test "list_contacts/1 with multiple contacts" do
      _c0 = contact_fixture(@valid_attrs)
      _c1 = contact_fixture(@valid_attrs_1)
      _c2 = contact_fixture(@valid_attrs_2)
      _c3 = contact_fixture(@valid_attrs_3)

      assert length(Contacts.list_contacts()) == 4
    end

    test "list_contacts/1 with multiple contacts sorted" do
      c0 = contact_fixture(@valid_attrs)
      c1 = contact_fixture(@valid_attrs_1)
      c2 = contact_fixture(@valid_attrs_2)
      c3 = contact_fixture(@valid_attrs_3)

      cs = Contacts.list_contacts(%{order: :asc})
      assert [c0, c1, c2, c3] == cs

      cs = Contacts.list_contacts(%{order: :desc})
      assert [c3, c2, c1, c0] == cs
    end

    test "list_contacts/1 with multiple contacts filtered" do
      c0 = contact_fixture(@valid_attrs)
      c1 = contact_fixture(@valid_attrs_1)
      _c2 = contact_fixture(@valid_attrs_2)
      c3 = contact_fixture(@valid_attrs_3)

      cs = Contacts.list_contacts(%{order: :asc, filter: %{phone: "some phone 3"}})
      assert cs == [c3]

      cs = Contacts.list_contacts(%{filter: %{phone: "some phone"}})
      assert length(cs) == 4

      cs = Contacts.list_contacts(%{order: :asc, filter: %{name: "some name 1"}})
      assert cs == [c1]

      cs =
        Contacts.list_contacts(%{
          order: :asc,
          filter: %{status: :valid, provider_status: :invalid}
        })

      assert cs == [c0]
    end

    test "upsert contacts" do
      c0 = contact_fixture(@valid_attrs)

      assert Contacts.upsert(%{phone: c0.phone, name: c0.name}).id == c0.id
    end

    test "ensure that creating contacts with same name/phone give an error" do
      contact_fixture(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Contacts.create_contact(@valid_attrs)
    end
  end
end
