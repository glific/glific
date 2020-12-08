defmodule Glific.ContactsTest do
  use Glific.DataCase, async: true

  alias Faker.Phone

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Partners,
    Partners.Organization,
    Seeds.SeedsDev,
    Settings,
    Settings.Language
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  describe "contacts" do
    @valid_attrs %{
      name: "some name",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: nil,
      phone: "some phone",
      status: :valid,
      bsp_status: :hsm,
      language_id: 1,
      fields: %{}
    }
    @valid_attrs_1 %{
      name: "some name 1",
      optin_time: nil,
      optout_time: nil,
      phone: "some phone 1",
      status: :invalid,
      bsp_status: :none,
      fields: %{}
    }
    @valid_attrs_2 %{
      name: "some name 2",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: nil,
      phone: "some phone 2",
      status: :valid,
      bsp_status: :hsm,
      fields: %{}
    }
    @valid_attrs_3 %{
      name: "some name 3",
      optin_time: DateTime.utc_now(),
      optout_time: nil,
      phone: "some phone 3",
      status: :invalid,
      bsp_status: :session_and_hsm,
      fields: %{}
    }
    @valid_attrs_to_test_order_1 %{
      name: "aaaa name",
      optin_time: nil,
      optout_time: nil,
      phone: "some phone 4",
      status: :valid,
      bsp_status: :none,
      fields: %{}
    }
    @valid_attrs_to_test_order_2 %{
      name: "zzzz name",
      optin_time: nil,
      optout_time: nil,
      phone: "some phone 5",
      status: :valid,
      bsp_status: :none,
      fields: %{}
    }
    @update_attrs %{
      name: "some updated name",
      optin_time: ~U[2011-05-18 15:01:01Z],
      optout_time: nil,
      phone: "some updated phone",
      status: :invalid,
      bsp_status: :hsm,
      fields: %{}
    }
    @invalid_attrs %{
      name: nil,
      optin_time: nil,
      optout_time: nil,
      phone: nil,
      status: nil,
      bsp_status: nil,
      fields: %{}
    }

    def contact_fixture(attrs) do
      {:ok, contact} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Contacts.create_contact()

      contact
    end

    test "list_contacts/1 returns all contacts", %{organization_id: _organization_id} = attrs do
      contacts_count = Contacts.count_contacts(%{filter: attrs})

      _contact = contact_fixture(attrs)
      assert length(Contacts.list_contacts(%{filter: attrs})) == contacts_count + 1
    end

    test "list_contacts/1 should remove blocked contacts unless filtered by status",
         %{organization_id: _organization_id} = attrs do
      contacts_count = Contacts.count_contacts(%{filter: attrs})

      _contact = contact_fixture(attrs |> Map.merge(%{status: :blocked}))
      assert length(Contacts.list_contacts(%{filter: attrs})) == contacts_count
    end

    test "count_contacts/0 returns count of all contacts",
         %{organization_id: _organization_id} = attrs do
      contacts_count = Contacts.count_contacts(%{filter: attrs})

      _ = contact_fixture(attrs)
      assert Contacts.count_contacts(%{filter: attrs}) == contacts_count + 1

      assert Contacts.count_contacts(%{filter: Map.merge(attrs, %{name: "some name"})}) == 1
    end

    test "get_contact!/1 returns the contact with given id",
         %{organization_id: _organization_id} = attrs do
      contact = contact_fixture(attrs)
      assert Contacts.get_contact!(contact.id) == contact
    end

    test "create_contact/1 with valid data creates a contact",
         %{organization_id: _organization_id} = attrs do
      attrs = Map.merge(attrs, @valid_attrs)
      assert {:ok, %Contact{} = contact} = Contacts.create_contact(attrs)
      assert contact.name == "some name"
      assert contact.optin_time == ~U[2010-04-17 14:00:00Z]
      assert contact.optout_time == nil
      assert contact.phone == "some phone"
      assert contact.status == :valid
      assert contact.bsp_status == :hsm

      # Contact should be created with organization's default language
      {:ok, organization} = Repo.fetch_by(Organization, %{name: "Glific"})

      assert contact.language_id == organization.default_language_id
    end

    test "create_contact/1 with language id creates a contact",
         %{organization_id: _organization_id} = attrs do
      {:ok, language} = Repo.fetch_by(Language, %{locale: "hi"})

      attrs =
        attrs
        |> Map.merge(@valid_attrs)
        |> Map.merge(%{language_id: language.id})

      assert {:ok, %Contact{} = contact} = Contacts.create_contact(attrs)
      assert contact.name == "some name"
      assert contact.optin_time == ~U[2010-04-17 14:00:00Z]
      assert contact.optout_time == nil
      assert contact.phone == "some phone"
      assert contact.status == :valid
      assert contact.bsp_status == :hsm
      assert contact.language_id == language.id
    end

    test "create_contact/1 with invalid data returns error changeset",
         %{organization_id: _organization_id} = attrs do
      attrs = Map.merge(attrs, @invalid_attrs)
      assert {:error, %Ecto.Changeset{}} = Contacts.create_contact(attrs)
    end

    test "update_contact/2 with valid data updates the contact",
         %{organization_id: _organization_id} = attrs do
      contact = contact_fixture(attrs)
      assert {:ok, %Contact{} = contact} = Contacts.update_contact(contact, @update_attrs)
      assert contact.name == "some updated name"
      assert contact.optin_time == ~U[2011-05-18 15:01:01Z]
      assert contact.optout_time == nil
      assert contact.phone == "some updated phone"
      assert contact.status == :invalid
      assert contact.bsp_status == :hsm
    end

    test "update_contact/2 with invalid data returns error changeset",
         %{organization_id: _organization_id} = attrs do
      contact = contact_fixture(attrs)
      assert {:error, %Ecto.Changeset{}} = Contacts.update_contact(contact, @invalid_attrs)
      assert contact == Contacts.get_contact!(contact.id)
    end

    test "delete_contact/1 deletes the contact", %{organization_id: _organization_id} = attrs do
      contact = contact_fixture(attrs)
      assert {:ok, %Contact{}} = Contacts.delete_contact(contact)
      assert_raise Ecto.NoResultsError, fn -> Contacts.get_contact!(contact.id) end
    end

    test "change_contact/1 returns a contact changeset",
         %{organization_id: _organization_id} = attrs do
      contact = contact_fixture(attrs)
      assert %Ecto.Changeset{} = Contacts.change_contact(contact)
    end

    test "list_contacts/1 with multiple contacts", %{organization_id: _organization_id} = attrs do
      contacts_count = Contacts.count_contacts(%{filter: attrs})

      _c0 = contact_fixture(Map.merge(attrs, @valid_attrs))
      _c1 = contact_fixture(Map.merge(attrs, @valid_attrs_1))
      _c2 = contact_fixture(Map.merge(attrs, @valid_attrs_2))
      _c3 = contact_fixture(Map.merge(attrs, @valid_attrs_3))

      assert length(Contacts.list_contacts(%{filter: attrs})) == contacts_count + 4
    end

    test "list_contacts/1 with multiple contacts sorted",
         %{organization_id: _organization_id} = attrs do
      contacts_count = Contacts.count_contacts(%{filter: attrs})

      c0 = contact_fixture(Map.merge(attrs, @valid_attrs_to_test_order_1))
      c1 = contact_fixture(Map.merge(attrs, @valid_attrs_to_test_order_2))

      assert length(Contacts.list_contacts(%{filter: attrs})) == contacts_count + 2

      [ordered_c0 | _] = Contacts.list_contacts(%{opts: %{order: :asc}, filter: attrs})
      assert c0 == ordered_c0

      [ordered_c1 | _] = Contacts.list_contacts(%{opts: %{order: :desc}, filter: attrs})
      assert c1 == ordered_c1
    end

    test "list_contacts/1 with multiple contacts filtered",
         %{organization_id: _organization_id} = attrs do
      c0 = contact_fixture(Map.merge(attrs, @valid_attrs))
      c1 = contact_fixture(Map.merge(attrs, @valid_attrs_1))
      c2 = contact_fixture(Map.merge(attrs, @valid_attrs_2))
      c3 = contact_fixture(Map.merge(attrs, @valid_attrs_3))

      cs =
        Contacts.list_contacts(%{
          opts: %{order: :asc},
          filter: Map.merge(attrs, %{phone: "some phone 3"})
        })

      assert cs == [c3]

      cs = Contacts.list_contacts(%{filter: Map.merge(attrs, %{phone: "some phone"})})
      assert length(cs) == 4

      cs =
        Contacts.list_contacts(%{
          opts: %{order: :asc},
          filter: Map.merge(attrs, %{name: "some name 1"})
        })

      assert cs == [c1]

      cs =
        Contacts.list_contacts(%{
          opts: %{order: :asc},
          filter: Map.merge(attrs, %{status: :valid, bsp_status: :hsm})
        })

      assert cs == [c0, c2]
    end

    test "upsert contacts", %{organization_id: organization_id} = attrs do
      c0 = contact_fixture(Map.merge(attrs, @valid_attrs))

      # check if the defualt language is set
      assert Partners.organization_language_id(organization_id) == c0.language_id

      {:ok, contact} =
        Contacts.upsert(%{
          phone: c0.phone,
          name: c0.name,
          organization_id: organization_id
        })

      assert contact.id == c0.id
    end

    test "ensure that upsert contacts overrides the language id",
         %{organization_id: organization_id} = attrs do
      c0 = contact_fixture(Map.merge(attrs, @valid_attrs))

      org_language_id = Partners.organization_language_id(organization_id)

      language =
        Settings.list_languages()
        |> Enum.find(fn ln -> ln.id != org_language_id end)

      {:ok, contact} =
        Contacts.upsert(%{
          phone: c0.phone,
          name: c0.name,
          language_id: language.id,
          organization_id: organization_id
        })

      assert contact.language_id == language.id
    end

    test "ensure that creating contacts with same name/phone give an error",
         %{organization_id: _organization_id} = attrs do
      contact_fixture(Map.merge(attrs, @valid_attrs))
      assert {:error, %Ecto.Changeset{}} = Contacts.create_contact(Map.merge(attrs, @valid_attrs))
    end

    test "ensure that contact returns the valid state for sending the message",
         %{organization_id: _organization_id} = attrs do
      contact =
        contact_fixture(
          Map.merge(
            attrs,
            %{
              bsp_status: :session_and_hsm,
              last_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
            }
          )
        )

      contact2 =
        contact_fixture(
          Map.merge(
            attrs,
            %{
              phone: Phone.EnUs.phone(),
              bsp_status: :none,
              last_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
            }
          )
        )

      contact3 =
        contact_fixture(
          Map.merge(
            attrs,
            %{
              phone: Phone.EnUs.phone(),
              bsp_status: :none,
              last_message_at: Timex.shift(DateTime.utc_now(), days: -2)
            }
          )
        )

      assert true == Contacts.can_send_message_to?(contact)
      assert false == Contacts.can_send_message_to?(contact2)
      assert false == Contacts.can_send_message_to?(contact3)
    end

    test "ensure that contact returns the valid state for sending the hsm message",
         %{organization_id: _organization_id} = attrs do
      contact1 =
        contact_fixture(
          Map.merge(
            attrs,
            %{
              phone: Phone.EnUs.phone(),
              bsp_status: :none
            }
          )
        )

      # When contact opts in, optout_time should be set to nil
      contact2 =
        contact_fixture(
          Map.merge(
            attrs,
            %{
              phone: Phone.EnUs.phone(),
              bsp_status: :session_and_hsm,
              optin_time: DateTime.utc_now(),
              optout_time: nil
            }
          )
        )

      contact3 =
        contact_fixture(
          Map.merge(
            attrs,
            %{
              phone: Phone.EnUs.phone(),
              bsp_status: :session_and_hsm,
              optin_time: nil
            }
          )
        )

      contact4 =
        contact_fixture(
          Map.merge(
            attrs,
            %{
              phone: Phone.EnUs.phone(),
              bsp_status: :session_and_hsm,
              optin_time: nil,
              optout_time: DateTime.utc_now()
            }
          )
        )

      assert false == Contacts.can_send_message_to?(contact1, true)
      assert true == Contacts.can_send_message_to?(contact2, true)
      assert false == Contacts.can_send_message_to?(contact3, true)
      assert false == Contacts.can_send_message_to?(contact4, true)
    end

    test "contact_opted_in/2 will setup the contact as valid contact for message",
         %{organization_id: organization_id} do
      contact = contact_fixture(%{organization_id: organization_id, status: :invalid})

      Contacts.contact_opted_in(contact.phone, organization_id, DateTime.utc_now())

      {:ok, contact} =
        Repo.fetch_by(
          Contact,
          %{phone: contact.phone, organization_id: organization_id}
        )

      assert contact.status == :valid
      assert contact.optin_time != nil
      assert contact.optout_time == nil

      # if the contact is blocked he want be able to optin again
      Contacts.update_contact(contact, %{status: :blocked})
      Contacts.contact_opted_in(contact.phone, organization_id, DateTime.utc_now())

      {:ok, contact} =
        Repo.fetch_by(
          Contact,
          %{phone: contact.phone, organization_id: organization_id}
        )

      assert contact.status == :blocked
    end

    test "contact_opted_out/2 will setup the contact as valid contact for message",
         %{organization_id: organization_id} do
      contact = contact_fixture(%{organization_id: organization_id, status: :valid})

      Contacts.contact_opted_out(contact.phone, organization_id, DateTime.utc_now())

      {:ok, contact} =
        Repo.fetch_by(
          Contact,
          %{phone: contact.phone, organization_id: organization_id}
        )

      assert contact.status == :invalid
      assert contact.optout_time != nil
    end

    test "set_session_status/2 will return :ok if contact list is empty" do
      assert :ok == Contacts.set_session_status([], :none)
    end

    test "set_session_status/2 will set provider status of not opted in contact",
         %{organization_id: organization_id} do
      contact =
        contact_fixture(%{
          organization_id: organization_id,
          bsp_status: :none,
          optin_time: nil
        })

      {:ok, contact} = Contacts.set_session_status(contact, :none)
      assert contact.bsp_status == :none

      {:ok, contact} = Contacts.set_session_status(contact, :session)
      assert contact.bsp_status == :session
    end

    test "set_session_status/2 will set provider status opted in contact",
         %{organization_id: organization_id} do
      contact =
        contact_fixture(%{
          organization_id: organization_id,
          bsp_status: :none,
          optin_time: DateTime.utc_now()
        })

      {:ok, contact} = Contacts.set_session_status(contact, :none)
      assert contact.bsp_status == :hsm

      {:ok, contact} = Contacts.set_session_status(contact, :session)
      assert contact.bsp_status == :session_and_hsm
    end

    test "update_contact_status should update the provider status",
         %{organization_id: organization_id} do
      contact =
        contact_fixture(%{
          organization_id: organization_id,
          bsp_status: :session_and_hsm,
          optin_time: Timex.shift(DateTime.utc_now(), hours: -25),
          last_message_at: Timex.shift(DateTime.utc_now(), hours: -24)
        })

      Contacts.update_contact_status(organization_id, nil)

      updated_contact = Contacts.get_contact!(contact.id)
      assert updated_contact.bsp_status == :hsm
    end

    test "is_contact_blocked?/2 will check if the contact is blocked",
         %{organization_id: _organization_id} = attrs do
      attrs = Map.merge(attrs, %{status: :blocked})
      contact = contact_fixture(attrs)
      assert Contacts.is_contact_blocked?(contact.phone, attrs.organization_id) == true
      Contacts.update_contact(contact, %{status: :valid})
      assert Contacts.is_contact_blocked?(contact.phone, attrs.organization_id) == false
    end
  end
end
