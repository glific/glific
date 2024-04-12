defmodule Glific.ContactsTest do
  use Glific.DataCase, async: true

  alias Faker.Phone
  import Mock

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.Import,
    Partners,
    Partners.Organization,
    Partners.Saas,
    Seeds.SeedsDev,
    Settings,
    Settings.Language,
    Users
  }

  setup do
    Tesla.Mock.mock_global(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200
        }

      %{method: :post} ->
        %Tesla.Env{
          status: 200
        }
    end)

    :ok
  end

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_groups()
    SeedsDev.seed_users()
    :ok
  end

  defp get_tmp_path(name \\ "fixture.csv") do
    System.tmp_dir!()
    |> Path.join(name)
  end

  defp get_tmp_file(name \\ "fixture.csv") do
    name
    |> get_tmp_path()
    |> File.open!([:write, :utf8])
  end

  describe "contacts" do
    @valid_attrs %{
      name: "some name",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optin_status: false,
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
      optin_status: false,
      optout_time: nil,
      phone: "some phone 1",
      status: :invalid,
      bsp_status: :none,
      fields: %{}
    }
    @valid_attrs_2 %{
      name: "some name 2",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optin_status: true,
      optout_time: nil,
      phone: "some phone 2",
      status: :valid,
      bsp_status: :hsm,
      fields: %{}
    }
    @valid_attrs_3 %{
      name: "some name 3",
      optin_time: DateTime.utc_now(),
      optin_status: true,
      optout_time: nil,
      phone: "some phone 3",
      status: :invalid,
      bsp_status: :session_and_hsm,
      fields: %{}
    }
    @valid_attrs_4 %{
      name: "some name 3",
      optin_time: DateTime.utc_now(),
      optin_status: true,
      optout_time: nil,
      phone: "919917443992",
      status: :invalid,
      bsp_status: :session_and_hsm,
      fields: %{}
    }
    @valid_attrs_to_test_order_1 %{
      name: "aaaa name",
      optin_time: nil,
      optin_status: false,
      optout_time: nil,
      phone: "some phone 4",
      status: :valid,
      bsp_status: :none,
      fields: %{}
    }
    @valid_attrs_to_test_order_2 %{
      name: "zzzz name",
      optin_time: nil,
      optin_status: false,
      optout_time: nil,
      phone: "some phone 5",
      status: :valid,
      bsp_status: :none,
      fields: %{}
    }
    @update_attrs %{
      name: "some updated name",
      optin_time: ~U[2011-05-18 15:01:01Z],
      optin_status: true,
      optout_time: nil,
      phone: "some updated phone",
      status: :invalid,
      bsp_status: :hsm,
      fields: %{}
    }
    @invalid_attrs %{
      name: nil,
      optin_time: nil,
      optin_status: false,
      optout_time: nil,
      phone: nil,
      status: nil,
      bsp_status: nil,
      fields: %{}
    }

    @invalid_field_attrs %{
      name: "name 3",
      optin_time: ~U[2011-05-18 15:01:01Z],
      optin_status: true,
      optout_time: nil,
      phone: "some updated phonenum",
      status: :invalid,
      bsp_status: :hsm,
      fields: %{label: "", name: "", inserted_at: ""}
    }

    @optin_date "2021-03-09 12:34:25"

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

    test "get_contact/1 returns the contact with given id and nil if does not exist",
         %{organization_id: _organization_id} = attrs do
      contact = contact_fixture(attrs)
      assert Contacts.get_contact(contact.id) == contact

      assert Contacts.get_contact(1_234_567) == nil
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

    test "create_contact/1 with fields should be nested map returns error changeset",
         %{organization_id: _organization_id} = attrs do
      attrs = Map.merge(attrs, @invalid_field_attrs)

      assert {:error,
              %Ecto.Changeset{
                errors: [
                  fields: {"value should be a map", []}
                ]
              }} = Contacts.create_contact(attrs)
    end

    test "create_contact/1 with invalid dateString in field map returns error changeset",
         %{organization_id: _organization_id} = attrs do
      invalid_time_attrs =
        Map.put(@invalid_field_attrs, :fields, %{
          "name" => %{
            label: "label",
            name: "name",
            inserted_at: "2024-10-03"
          }
        })

      attrs = Map.merge(attrs, invalid_time_attrs)

      assert {:error,
              %Ecto.Changeset{
                errors: [
                  fields:
                    {"Expected value of inserted_at to be of type DateTime.t() and non-empty", []}
                ]
              }} = Contacts.create_contact(attrs)
    end

    test "create_contact/1 with valid dateString in field map",
         %{organization_id: _organization_id} = attrs do
      valid_time_attrs =
        Map.put(@invalid_field_attrs, :fields, %{
          "name" => %{
            label: "label",
            name: "name",
            inserted_at: ~U[2024-04-05 06:51:07.544495Z]
          }
        })

      attrs = Map.merge(attrs, valid_time_attrs)
      assert {:ok, _} = Contacts.create_contact(attrs)
    end

    test "create_contact/1 with invalid type in field map returns error changeset, list instead of string",
         %{organization_id: _organization_id} = attrs do
      valid_time_attrs =
        Map.put(@invalid_field_attrs, :fields, %{
          "title" => %{
            label: "label",
            name: "title",
            values: "titles",
            inserted_at: "2024-04-05T05:35:22.265996Z"
          },
          "name" => %{
            label: "label",
            name: ["name1", "name2"],
            values: "values",
            inserted_at: "2024-04-05T05:35:22.265996Z"
          }
        })

      attrs = Map.merge(attrs, valid_time_attrs)

      assert {:error,
              %Ecto.Changeset{
                errors: [
                  fields: {"Expected value of name to be of type String and non-empty", []}
                ]
              }} = Contacts.create_contact(attrs)
    end

    test "create_contact/1 with empty field map",
         %{organization_id: _organization_id} = attrs do
      valid_time_attrs =
        Map.put(@invalid_field_attrs, :fields, %{})

      attrs = Map.merge(attrs, valid_time_attrs)

      assert {:ok, _} = Contacts.create_contact(attrs)
    end

    test "import_contact/3 raises an exception if more than one keyword argument provided" do
      assert_raise RuntimeError, fn ->
        Import.import_contacts(999, "admin",
          file_path: "file_path",
          url: ""
        )
      end
    end

    test "maybe_update_contact/1  with valid data updates the contact",
         %{organization_id: _organization_id} = attrs do
      contact = contact_fixture(attrs)

      update_attrs = %{
        name: "some updated name",
        optin_time: ~U[2011-05-18 15:01:01Z],
        optin_status: true,
        optout_time: nil,
        phone: contact.phone,
        status: :invalid,
        bsp_status: :hsm,
        fields: %{}
      }

      assert {:ok, %Contact{} = contact} = Contacts.maybe_update_contact(update_attrs)
      assert contact.name == "some updated name"
      assert contact.optin_time == ~U[2011-05-18 15:01:01Z]
      assert contact.optout_time == nil
      assert contact.status == :invalid
      assert contact.bsp_status == :hsm
    end

    test "maybe_update_contact/1 with invalid phone number which is not in DB",
         %{organization_id: _organization_id} = attrs do
      contact_fixture(attrs)

      {:error, error} = Contacts.maybe_update_contact(@update_attrs)
      assert error == "Contact some updated phone was not found and hence not added"
    end

    test "import_contact/3 with valid data from file inserts new contacts in the database" do
      file = get_tmp_file()

      [
        ~w(name phone Language opt_in collection),
        ["test", "9989329297", "english", @optin_date, "collection"]
      ]
      |> CSV.encode()
      |> Enum.each(&IO.write(file, &1))

      [organization | _] = Partners.list_organizations()
      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})
      user = Map.put(user, :roles, [:glific_admin])

      Import.import_contacts(organization.id, %{user: user, collection: "collection"},
        file_path: get_tmp_path()
      )

      count = Contacts.count_contacts(%{filter: %{name: "test"}})

      assert count == 1
    end

    test "import_contact/3 with valid data from string inserts new contacts in the database" do
      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})
      user = Map.put(user, :roles, [:glific_admin])

      data = "name,phone,Language,opt_in\ncontact_test,9989329297,english,2021-03-09 12:34:25\n"

      [organization | _] = Partners.list_organizations()

      Import.import_contacts(organization.id, %{user: user, collection: "collection"}, data: data)
      count = Contacts.count_contacts(%{filter: %{phone: "9989329297"}})

      assert count == 1
    end

    test "import_contact/3 with valid data from URL inserts new contacts in the database" do
      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})
      user = Map.put(user, :roles, [:glific_admin])

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }

        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "name,phone,Language,opt_in\ntest,9989329297,english,2021-03-09 12:34:25\n"
          }
      end)

      [organization | _] = Partners.list_organizations()

      Import.import_contacts(organization.id, %{user: user, collection: "collection"},
        url: "http://www.bar.com/foo.csv"
      )

      count = Contacts.count_contacts(%{filter: %{name: "test"}})

      assert count == 1
    end

    test "import_contact/3 can creates the contact in the db if upload contacts is enabled" do
      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})

      user =
        user
        |> Map.put(:roles, [:staff])
        |> Map.put(:upload_contacts, true)

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }

        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "name,phone,Language,opt_in\ntest,9989329297,english,2021-03-09 12:34:25\n"
          }
      end)

      [organization | _] = Partners.list_organizations()

      Import.import_contacts(organization.id, %{user: user, collection: "collection"},
        url: "http://www.bar.com/foo.csv"
      )

      count = Contacts.count_contacts(%{filter: %{name: "test"}})

      assert count == 1
    end

    test "import_contact/3 with valid data from file updates existing contacts in the database",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }
      end)

      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})

      file = get_tmp_file()
      {:ok, contact} = Contacts.create_contact(Map.merge(attrs, @valid_attrs_4))

      [
        ~w(name phone Language opt_in collection),
        ["updated", "#{contact.phone}", "english", @optin_date, "collection"]
      ]
      |> CSV.encode()
      |> Enum.each(&IO.write(file, &1))

      [organization | _] = Partners.list_organizations()

      Import.import_contacts(organization.id, %{user: user}, file_path: get_tmp_path())

      count = Contacts.count_contacts(%{filter: %{name: "updated", phone: contact.phone}})

      assert count == 1
    end

    test "import_contact/3 with valid data from string updates existing contacts in the database",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }
      end)

      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})

      {:ok, contact} = Contacts.create_contact(Map.merge(attrs, @valid_attrs_4))

      data =
        "name,phone,Language,opt_in,collection\nupdated,#{contact.phone},english,2021-03-09 12:34:25,collection\n"

      [organization | _] = Partners.list_organizations()

      Import.import_contacts(organization.id, %{user: user}, data: data)
      count = Contacts.count_contacts(%{filter: %{name: "updated", phone: contact.phone}})

      assert count == 1
    end

    test "import_contact/3 with valid data from URL updates existing contacts in the database",
         attrs do
      {:ok, contact} = Contacts.create_contact(Map.merge(attrs, @valid_attrs_4))

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }

        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              "name,phone,Language,opt_in,collection\nupdated,#{contact.phone},english,2021-03-09 12:34:25,collection\n"
          }
      end)

      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})

      [organization | _] = Partners.list_organizations()

      Import.import_contacts(organization.id, %{user: user}, url: "http://www.bar.com/foo.csv")

      count = Contacts.count_contacts(%{filter: %{name: "updated", phone: contact.phone}})

      assert count == 1
    end

    test "import_contact/3 deletes contacts when delete=1 column is present", attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }
      end)

      file = get_tmp_file()
      {:ok, contact} = Contacts.create_contact(Map.merge(attrs, @valid_attrs_4))
      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})
      user = Map.put(user, :roles, [:glific_admin])

      [
        ~w(name phone Language opt_in delete),
        ["updated", "#{contact.phone}", "english", @optin_date, 1]
      ]
      |> CSV.encode()
      |> Enum.each(&IO.write(file, &1))

      [organization | _] = Partners.list_organizations()

      Import.import_contacts(organization.id, %{user: user, collection: "collection"},
        file_path: get_tmp_path()
      )

      count = Contacts.count_contacts(%{filter: %{phone: contact.phone}})

      assert count == 0
    end

    test "import_contact/3 deletes contacts when delete=1 column is present and if permission is not given",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }
      end)

      file = get_tmp_file()
      {:ok, contact} = Contacts.create_contact(Map.merge(attrs, @valid_attrs_4))
      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})

      [
        ~w(name phone Language opt_in delete collection),
        ["updated", "#{contact.phone}", "english", @optin_date, 1, "collection"]
      ]
      |> CSV.encode()
      |> Enum.each(&IO.write(file, &1))

      [organization | _] = Partners.list_organizations()

      {:error, message} =
        Import.import_contacts(organization.id, %{user: user, collection: "collection"},
          file_path: get_tmp_path()
        )

      assert message == ["This user doesn't have enough permission"]

      count = Contacts.count_contacts(%{filter: %{phone: contact.phone}})

      assert count == 1
    end

    test "import_contact/3 ignores delete if the contact already deleted", attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }
      end)

      file = get_tmp_file()
      {:ok, contact} = Contacts.create_contact(Map.merge(attrs, @valid_attrs_4))
      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})
      user = Map.put(user, :roles, [:glific_admin])
      Contacts.delete_contact(contact)

      [
        ~w(name phone Language opt_in delete),
        ["updated", "#{contact.phone}", "english", @optin_date, 1]
      ]
      |> CSV.encode()
      |> Enum.each(&IO.write(file, &1))

      [organization | _] = Partners.list_organizations()

      Import.import_contacts(organization.id, %{user: user, collection: "collection"},
        file_path: get_tmp_path()
      )

      count = Contacts.count_contacts(%{filter: %{phone: contact.phone}})

      assert count == 0
    end

    test "import_contact/3 does not call glific opt_in api if column empty" do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }
      end)

      with_mocks([
        {
          Contacts,
          [:passthrough],
          [optin_contact: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
        }
      ]) do
        file = get_tmp_file()

        [~w(name phone Language opt_in)]
        |> Enum.concat([["updated", "9989329297", "english", ""]])
        |> CSV.encode()
        |> Enum.each(&IO.write(file, &1))

        [organization | _] = Partners.list_organizations()

        {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})
        user = Map.put(user, :roles, [:glific_admin])

        Import.import_contacts(organization.id, %{user: user, collection: "collection"},
          file_path: get_tmp_path()
        )

        count = Contacts.count_contacts(%{filter: %{phone: 9_989_329_297}})

        [contact | _tail] = Contacts.list_contacts(%{filter: %{phone: 9_989_329_297}})

        assert get_in(contact.fields, ["name", "value"]) == "updated"

        assert count == 1
        assert_not_called(Contacts.optin_contact())
      end
    end

    test "import_contact/3 with invalid organization id returns an error" do
      Tesla.Mock.mock_global(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }
      end)

      file = get_tmp_file()

      [~w(name phone Language opt_in), ["test", "9989329297", "english", @optin_date]]
      |> CSV.encode()
      |> Enum.each(&IO.write(file, &1))

      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})

      assert {:error, _} =
               Import.import_contacts(999, %{user: user, collection: "collection"},
                 file_path: get_tmp_path()
               )
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

    test "delete_contact/1 does not deletes the contact when contact is organization contact",
         %{organization_id: organization_id} = _attrs do
      org = Partners.organization(organization_id)
      assert {:error, error} = Contacts.delete_contact(org.contact)
      assert error == "Sorry, this is your chatbot number and hence cannot be deleted."
    end

    test "delete_contact/1 raises error when does not have permission" do
      admin_user = Repo.get_current_user()

      with {:ok, user} <- Repo.fetch_by(Users.User, %{name: "NGO Staff"}),
           {:ok, restricted_user} <- Users.update_user(user, %{is_restricted: true}) do
        Repo.put_current_user(restricted_user)
      end

      {:ok, contact} = Repo.fetch_by(Contacts.Contact, %{name: "SaaS Admin"})

      assert_raise RuntimeError, fn ->
        Contacts.delete_contact(contact)
      end

      # restore state
      Repo.put_current_user(admin_user)
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

      opted_out_contact =
        contact_fixture(
          Map.merge(
            attrs,
            %{
              phone: Phone.EnUs.phone(),
              bsp_status: :hsm,
              optout_time: DateTime.utc_now(),
              last_message_at: Timex.shift(DateTime.utc_now(), days: -2)
            }
          )
        )

      assert {:ok, _} = Contacts.can_send_message_to?(contact)
      assert {:error, _} = Contacts.can_send_message_to?(contact2)
      assert {:error, _} = Contacts.can_send_message_to?(contact3)

      assert {:ok, _} =
               Contacts.can_send_message_to?(opted_out_contact, true, %{is_optin_flow: true})

      assert {:error, _} =
               Contacts.can_send_message_to?(opted_out_contact, false, %{is_optin_flow: true})
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
              optin_status: true,
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
              optin_time: nil,
              optin_status: false
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
              optin_status: false,
              optout_time: DateTime.utc_now()
            }
          )
        )

      assert {:error, _} = Contacts.can_send_message_to?(contact1, true)
      assert {:ok, _} = Contacts.can_send_message_to?(contact2, true)
      assert {:error, _} = Contacts.can_send_message_to?(contact3, true)
      assert {:error, _} = Contacts.can_send_message_to?(contact4, true)
    end

    test "contact_opted_in/2 will setup the contact as valid contact for message",
         %{organization_id: organization_id} = attrs do
      contact = contact_fixture(%{organization_id: organization_id, status: :invalid})

      optin_time = DateTime.utc_now()
      message_id = Ecto.UUID.generate()

      Contacts.contact_opted_in(%{phone: contact.phone}, organization_id, optin_time,
        method: "Testing",
        message_id: message_id
      )

      [history | _tail] =
        Contacts.list_contact_history(
          Map.merge(attrs, %{filter: %{contact_id: contact.id, event_type: "contact_opted_in"}})
        )

      assert history.event_meta["method"] == "Testing"
      assert history.event_meta["optin_message_id"] == message_id

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
      Contacts.contact_opted_in(%{phone: contact.phone}, organization_id, DateTime.utc_now())

      {:ok, contact} =
        Repo.fetch_by(
          Contact,
          %{phone: contact.phone, organization_id: organization_id}
        )

      assert contact.status == :blocked
    end

    test "contact_opted_out/2 will setup the contact as valid contact for message",
         %{organization_id: organization_id} = attrs do
      contact = contact_fixture(%{organization_id: organization_id, status: :valid})

      Contacts.contact_opted_out(
        contact.phone,
        organization_id,
        DateTime.utc_now(),
        "OptedoutTesting"
      )

      {:ok, contact} =
        Repo.fetch_by(
          Contact,
          %{phone: contact.phone, organization_id: organization_id}
        )

      assert contact.status == :invalid
      assert contact.optout_time != nil

      [history | _tail] =
        Contacts.list_contact_history(
          Map.merge(attrs, %{filter: %{contact_id: contact.id, event_type: "contact_opted_out"}})
        )

      assert history.event_meta["method"] == "OptedoutTesting"

      assert Contacts.contact_opted_out("8910928313", organization_id, DateTime.utc_now()) ==
               :error
    end

    test "maybe_create_contact/1 will update contact name", %{organization_id: organization_id} do
      contact = contact_fixture(%{organization_id: organization_id, status: :valid})
      sender = %{name: "demo phone 2", organization_id: 1, phone: contact.phone}
      Contacts.maybe_create_contact(sender)
      contact = Contacts.get_contact!(contact.id)
      assert "demo phone 2" == contact.name
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
          optin_time: nil,
          optin_status: false
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
          optin_time: DateTime.utc_now(),
          optin_status: true
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
          optin_status: true,
          last_message_at: Timex.shift(DateTime.utc_now(), hours: -24)
        })

      Contacts.update_contact_status(organization_id, nil)

      updated_contact = Contacts.get_contact!(contact.id)
      assert updated_contact.bsp_status == :hsm
    end

    test "contact_blocked?/1 will check if the contact is blocked",
         %{organization_id: _organization_id} = attrs do
      attrs = Map.merge(attrs, %{status: :blocked})
      contact = contact_fixture(attrs)
      assert Contacts.contact_blocked?(contact) == true
      {:ok, contact} = Contacts.update_contact(contact, %{status: :valid})
      assert Contacts.contact_blocked?(Map.put(contact, :phone, "9123456")) == false
    end

    test "getting saas variables" do
      assert "91111222333" == Saas.phone()
    end
  end
end
