defmodule Glific.ContactsTest do
  use Glific.DataCase, async: true

  alias Faker.Phone
  alias Glific.Contacts

  describe "contacts" do
    alias Glific.Contacts.Contact
    alias Glific.Partners
    alias Glific.Settings

    @valid_default_language_attrs %{
      label: "English (United States)",
      label_locale: "English",
      locale: "en_US",
      is_active: true
    }
    @valid_provider_attrs %{
      name: "some name",
      url: "some url",
      api_end_point: "some api_end_point"
    }
    @valid_org_attrs %{
      name: "Organization Name",
      display_name: "Organization Display Name",
      contact_name: "Organization Contact person",
      email: "Contact person email",
      provider_key: "Provider key",
      provider_number: "991737373"
    }

    def default_language_fixture(attrs \\ %{}) do
      {:ok, default_language} =
        attrs
        |> Enum.into(@valid_default_language_attrs)
        |> Settings.language_upsert()

      default_language
    end

    def provider_fixture() do
      {:ok, provider} =
        @valid_provider_attrs
        |> Partners.create_provider()

      provider
    end

    def organization_fixture(attrs \\ %{}) do
      default_language = default_language_fixture(attrs)
      provider = provider_fixture()

      {:ok, organization} =
        attrs
        |> Enum.into(@valid_org_attrs)
        |> Map.merge(%{provider_id: provider.id, default_language_id: default_language.id})
        |> Partners.create_organization()

      organization
    end

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
      organization_fixture()

      contact = contact_fixture()
      assert Contacts.list_contacts() == [contact]
    end

    test "count_contacts/0 returns count of all contacts" do
      organization_fixture()

      _ = contact_fixture()
      assert Contacts.count_contacts() == 1

      assert Contacts.count_contacts(%{filter: %{name: "some name"}}) == 1
    end

    test "get_contact!/1 returns the contact with given id" do
      organization_fixture()

      contact = contact_fixture()
      assert Contacts.get_contact!(contact.id) == contact
    end

    test "create_contact/1 with valid data creates a contact" do
      organization_fixture()

      assert {:ok, %Contact{} = contact} = Contacts.create_contact(@valid_attrs)
      assert contact.name == "some name"
      assert contact.optin_time == ~U[2010-04-17 14:00:00Z]
      assert contact.optout_time == ~U[2010-04-17 14:00:00Z]
      assert contact.phone == "some phone"
      assert contact.status == :valid
      assert contact.provider_status == :invalid
    end

    test "create_contact/1 with invalid data returns error changeset" do
      organization_fixture()

      assert {:error, %Ecto.Changeset{}} = Contacts.create_contact(@invalid_attrs)
    end

    test "update_contact/2 with valid data updates the contact" do
      organization_fixture()

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
      organization_fixture()

      contact = contact_fixture()
      assert {:error, %Ecto.Changeset{}} = Contacts.update_contact(contact, @invalid_attrs)
      assert contact == Contacts.get_contact!(contact.id)
    end

    test "delete_contact/1 deletes the contact" do
      organization_fixture()

      contact = contact_fixture()
      assert {:ok, %Contact{}} = Contacts.delete_contact(contact)
      assert_raise Ecto.NoResultsError, fn -> Contacts.get_contact!(contact.id) end
    end

    test "change_contact/1 returns a contact changeset" do
      organization_fixture()

      contact = contact_fixture()
      assert %Ecto.Changeset{} = Contacts.change_contact(contact)
    end

    test "list_contacts/1 with multiple contacts" do
      organization_fixture()

      _c0 = contact_fixture(@valid_attrs)
      _c1 = contact_fixture(@valid_attrs_1)
      _c2 = contact_fixture(@valid_attrs_2)
      _c3 = contact_fixture(@valid_attrs_3)

      assert length(Contacts.list_contacts()) == 4
    end

    test "list_contacts/1 with multiple contacts sorted" do
      organization_fixture()

      c0 = contact_fixture(@valid_attrs)
      c1 = contact_fixture(@valid_attrs_1)
      c2 = contact_fixture(@valid_attrs_2)
      c3 = contact_fixture(@valid_attrs_3)

      cs = Contacts.list_contacts(%{opts: %{order: :asc}})
      assert [c0, c1, c2, c3] == cs

      cs = Contacts.list_contacts(%{opts: %{order: :desc}})
      assert [c3, c2, c1, c0] == cs
    end

    test "list_contacts/1 with multiple contacts filtered" do
      organization_fixture()

      c0 = contact_fixture(@valid_attrs)
      c1 = contact_fixture(@valid_attrs_1)
      _c2 = contact_fixture(@valid_attrs_2)
      c3 = contact_fixture(@valid_attrs_3)

      cs = Contacts.list_contacts(%{opts: %{order: :asc}, filter: %{phone: "some phone 3"}})
      assert cs == [c3]

      cs = Contacts.list_contacts(%{filter: %{phone: "some phone"}})
      assert length(cs) == 4

      cs = Contacts.list_contacts(%{opts: %{order: :asc}, filter: %{name: "some name 1"}})
      assert cs == [c1]

      cs =
        Contacts.list_contacts(%{
          opts: %{order: :asc},
          filter: %{status: :valid, provider_status: :invalid}
        })

      assert cs == [c0]
    end

    test "upsert contacts" do
      org = organization_fixture()

      c0 = contact_fixture(@valid_attrs)

      assert Contacts.upsert(%{
               phone: c0.phone,
               name: c0.name,
               language_id: org.default_language_id
             }).id == c0.id
    end

    test "ensure that creating contacts with same name/phone give an error" do
      organization_fixture()

      contact_fixture(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Contacts.create_contact(@valid_attrs)
    end

    test "ensure that contact returns the valid state for sending the message" do
      organization_fixture()

      contact =
        contact_fixture(%{
          provider_status: :valid,
          last_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      contact2 =
        contact_fixture(%{
          phone: Phone.EnUs.phone(),
          provider_status: :invalid,
          last_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      contact3 =
        contact_fixture(%{
          phone: Phone.EnUs.phone(),
          provider_status: :valid,
          last_message_at: Timex.shift(DateTime.utc_now(), days: -2)
        })

      assert true == Contacts.can_send_message_to?(contact)
      assert false == Contacts.can_send_message_to?(contact2)
      assert false == Contacts.can_send_message_to?(contact3)
    end
  end
end
