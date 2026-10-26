defmodule GlificWeb.Schema.ContactIdentityTest do
  # Not async: it flips global FunWithFlags flags and writes the organization's credential.
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Contacts.ContactIdentity,
    Fixtures,
    Repo,
    WebChannelFlagHelpers
  }

  load_gql(:by_identity, GlificWeb.Schema, "assets/gql/contact_identities/by_identity.gql")
  load_gql(:add, GlificWeb.Schema, "assets/gql/contact_identities/add.gql")
  load_gql(:create_contact, GlificWeb.Schema, "assets/gql/contact_identities/create_contact.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/contact_identities/list.gql")
  load_gql(:optin_contact, GlificWeb.Schema, "assets/gql/contacts/optin_contact.gql")

  setup do
    WebChannelFlagHelpers.reset_web_channel_flag(1)
    :ok
  end

  defp with_web_channel(fun),
    do: WebChannelFlagHelpers.with_web_channel_enabled(1, fun)

  defp web_input(attrs),
    do: %{"input" => Map.merge(%{"channel" => "WEB", "identifier" => "ravi_12"}, attrs)}

  defp add_variables(contact, attrs \\ %{}),
    do:
      Map.merge(
        %{"contactId" => to_string(contact.id), "channel" => "WEB", "identifier" => "ravi_12"},
        attrs
      )

  describe "createContact on the web channel" do
    test "creates a contact without a phone and with its web identity", %{manager: user} do
      with_web_channel(fn ->
        assert {:ok, query_data} =
                 auth_query_gql_by(:create_contact, user,
                   variables: web_input(%{"name" => "Ravi"})
                 )

        assert %{
                 "id" => contact_id,
                 "name" => "Ravi",
                 "identities" => [%{"channel" => "WEB", "identifier" => "ravi_12"}]
               } = get_in(query_data, [:data, "createContact", "contact"])

        assert %{contact_id: id} =
                 Repo.get_by!(ContactIdentity, %{channel: :web, identifier: "ravi_12"})

        assert to_string(id) == contact_id
        assert nil == Repo.get(Glific.Contacts.Contact, id).phone
      end)
    end

    test "requires an identifier", %{manager: user} do
      with_web_channel(fn ->
        {:ok, query_data} =
          auth_query_gql_by(:create_contact, user,
            variables: %{"input" => %{"channel" => "WEB", "name" => "Ravi"}}
          )

        assert [%{"key" => "Identifier", "message" => message}] =
                 get_in(query_data, [:data, "createContact", "errors"])

        assert message =~ "required"
      end)
    end

    test "is refused while the web channel is off", %{manager: user} do
      assert {:ok, query_data} =
               auth_query_gql_by(:create_contact, user, variables: web_input(%{}))

      assert [%{"message" => message}] = get_in(query_data, [:data, "createContact", "errors"])
      assert message =~ "not enabled"
      assert nil == Repo.get_by(ContactIdentity, %{identifier: "ravi_12"})
    end

    test "an identifier longer than 255 characters is refused", %{manager: user} do
      with_web_channel(fn ->
        {:ok, query_data} =
          auth_query_gql_by(:create_contact, user,
            variables: web_input(%{"identifier" => String.duplicate("a", 256)})
          )

        assert [%{"message" => _}] = get_in(query_data, [:data, "createContact", "errors"])
      end)
    end

    test "without a channel it still creates a WhatsApp contact", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:create_contact, user,
          variables: %{"input" => %{"name" => "Plain", "phone" => "919876500777"}}
        )

      assert %{"identities" => [%{"channel" => "WHATSAPP", "identifier" => "919876500777"}]} =
               get_in(query_data, [:data, "createContact", "contact"])
    end

    test "an identifier without the web channel is refused", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:create_contact, user,
          variables: %{
            "input" => %{"name" => "Mixed", "phone" => "919876500778", "identifier" => "ravi_12"}
          }
        )

      assert [%{"key" => "Identifier"}] = get_in(query_data, [:data, "createContact", "errors"])
    end

    test "a WhatsApp contact still needs a phone", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:create_contact, user, variables: %{"input" => %{"name" => "No phone"}})

      assert [%{"key" => "phone"}] = get_in(query_data, [:data, "createContact", "errors"])
    end
  end

  describe "addContactIdentity" do
    setup do
      %{contact: Fixtures.contact_without_phone_fixture()}
    end

    test "a manager adds a web identity", %{manager: user, contact: contact} do
      with_web_channel(fn ->
        assert {:ok, query_data} =
                 auth_query_gql_by(:add, user,
                   variables: add_variables(contact, %{"identifier" => "Ravi_12"})
                 )

        assert [%{"channel" => "WEB", "identifier" => "ravi_12"}] =
                 get_in(query_data, [:data, "addContactIdentity", "contact", "identities"])
      end)
    end

    test "adding the same identity to the same contact is idempotent", %{
      manager: user,
      contact: contact
    } do
      with_web_channel(fn ->
        {:ok, _first} = auth_query_gql_by(:add, user, variables: add_variables(contact))
        {:ok, second} = auth_query_gql_by(:add, user, variables: add_variables(contact))

        assert nil == get_in(second, [:data, "addContactIdentity", "errors"])

        assert 1 ==
                 ContactIdentity
                 |> where([i], i.identifier == "ravi_12")
                 |> Repo.aggregate(:count)
      end)
    end

    test "an identifier held by another contact is refused and not moved", %{
      manager: user,
      contact: contact
    } do
      with_web_channel(fn ->
        other = Fixtures.contact_without_phone_fixture()
        Fixtures.contact_identity_fixture(%{contact_id: other.id, identifier: "ravi_12"})

        {:ok, query_data} = auth_query_gql_by(:add, user, variables: add_variables(contact))

        assert [%{"key" => "identifier", "message" => "Identifier: has already been taken"}] =
                 get_in(query_data, [:data, "addContactIdentity", "errors"])

        assert %{contact_id: owner_id} = Repo.get_by!(ContactIdentity, %{identifier: "ravi_12"})
        assert owner_id == other.id
      end)
    end

    test "only the web channel can be added", %{manager: user, contact: contact} do
      {:ok, query_data} =
        auth_query_gql_by(:add, user,
          variables: add_variables(contact, %{"channel" => "WHATSAPP"})
        )

      assert [%{"key" => "channel"}] = get_in(query_data, [:data, "addContactIdentity", "errors"])
    end

    test "is refused while the web channel is off", %{manager: user, contact: contact} do
      {:ok, query_data} = auth_query_gql_by(:add, user, variables: add_variables(contact))

      assert [%{"message" => message}] =
               get_in(query_data, [:data, "addContactIdentity", "errors"])

      assert message =~ "not enabled"
    end

    test "a contact of another organization is not found", %{manager: user} do
      with_web_channel(fn ->
        other_organization = Fixtures.organization_fixture()

        foreign =
          Fixtures.contact_without_phone_fixture(%{organization_id: other_organization.id})

        {:ok, query_data} = auth_query_gql_by(:add, user, variables: add_variables(foreign))

        assert [%{"message" => "Resource not found"}] =
                 get_in(query_data, [:data, "addContactIdentity", "errors"])

        assert nil ==
                 Repo.get_by(ContactIdentity, %{identifier: "ravi_12"},
                   skip_organization_id: true
                 )
      end)
    end

    test "a staff user is refused", %{staff: user, contact: contact} do
      with_web_channel(fn ->
        assert {:ok, query_data} =
                 auth_query_gql_by(:add, user, variables: add_variables(contact))

        assert [%{message: "Unauthorized"}] = query_data.errors
        assert nil == Repo.get_by(ContactIdentity, %{identifier: "ravi_12"})
      end)
    end
  end

  describe "contactByIdentity" do
    setup do
      contact = Fixtures.contact_without_phone_fixture()
      Fixtures.contact_identity_fixture(%{contact_id: contact.id, identifier: "ravi_12"})
      %{contact: contact}
    end

    defp by_identity(user, identifier, channel \\ "WEB"),
      do:
        auth_query_gql_by(:by_identity, user,
          variables: %{"channel" => channel, "identifier" => identifier}
        )

    test "finds the contact, ignoring the case of a web identifier", %{
      manager: user,
      contact: contact
    } do
      assert {:ok, query_data} = by_identity(user, "RAVI_12")

      assert get_in(query_data, [:data, "contactByIdentity", "contact", "id"]) ==
               to_string(contact.id)
    end

    test "finds a contact by its whatsapp identity", %{manager: user} do
      contact = Fixtures.contact_fixture(%{phone: "919876500777"})

      assert {:ok, query_data} = by_identity(user, "919876500777", "WHATSAPP")

      assert get_in(query_data, [:data, "contactByIdentity", "contact", "id"]) ==
               to_string(contact.id)
    end

    test "a whatsapp lookup through contacts.phone does not write an identity row", %{
      manager: user
    } do
      contact = Fixtures.contact_fixture(%{phone: "919876500778"})
      Repo.delete_all(from(i in ContactIdentity, where: i.contact_id == ^contact.id))

      assert {:ok, query_data} = by_identity(user, "919876500778", "WHATSAPP")

      assert get_in(query_data, [:data, "contactByIdentity", "contact", "id"]) ==
               to_string(contact.id)

      assert [] == Repo.all(from(i in ContactIdentity, where: i.contact_id == ^contact.id))
    end

    test "returns an error when no contact has the identifier", %{manager: user} do
      assert {:ok, query_data} = by_identity(user, "nobody")

      assert %{"contact" => nil, "errors" => [%{"key" => "Contact", "message" => message}]} =
               get_in(query_data, [:data, "contactByIdentity"])

      assert message =~ "not found"
    end

    test "does not create a contact", %{manager: user} do
      assert {:ok, _query_data} = by_identity(user, "nobody")
      assert nil == Repo.get_by(ContactIdentity, %{identifier: "nobody"})
    end

    test "does not find an identity of another organization", %{manager: user} do
      other_organization = Fixtures.organization_fixture()

      other =
        Fixtures.contact_without_phone_fixture(%{organization_id: other_organization.id})

      Fixtures.contact_identity_fixture(%{
        contact_id: other.id,
        organization_id: other_organization.id,
        identifier: "other_org_user"
      })

      Repo.put_organization_id(user.organization_id)

      assert {:ok, query_data} = by_identity(user, "other_org_user")
      assert nil == get_in(query_data, [:data, "contactByIdentity", "contact"])
    end

    test "a staff user is refused", %{staff: user} do
      assert {:ok, query_data} = by_identity(user, "ravi_12")

      assert [%{message: "Unauthorized"}] = query_data.errors
    end
  end

  describe "identities on a contact" do
    setup do
      contact = Fixtures.contact_without_phone_fixture()
      Fixtures.contact_identity_fixture(%{contact_id: contact.id, identifier: "ravi_12"})
      %{contact: contact}
    end

    defp identities_of(query_data, contact) do
      query_data
      |> get_in([:data, "contacts"])
      |> Enum.find(&(&1["id"] == to_string(contact.id)))
      |> Map.fetch!("identities")
    end

    defp list_identities(user),
      do:
        auth_query_gql_by(:list, user, variables: %{"filter" => %{}, "opts" => %{"limit" => 100}})

    test "a manager sees them", %{manager: user, contact: contact} do
      assert {:ok, query_data} = list_identities(user)

      assert [%{"channel" => "WEB", "identifier" => "ravi_12", "id" => _, "insertedAt" => _}] =
               identities_of(query_data, contact)
    end

    test "an admin sees them", %{user: user, contact: contact} do
      assert {:ok, query_data} = list_identities(user)

      assert [%{"identifier" => "ravi_12"}] = identities_of(query_data, contact)
    end

    test "a staff user gets none", %{staff: user, contact: contact} do
      assert {:ok, query_data} = list_identities(user)

      assert [] == identities_of(query_data, contact)
    end

    test "loading them for many contacts costs one identities query", %{manager: user} do
      for _ <- 1..3 do
        contact = Fixtures.contact_without_phone_fixture()
        Fixtures.contact_identity_fixture(%{contact_id: contact.id})
      end

      handler = "identity-query-counter-#{System.unique_integer()}"
      test_pid = self()

      :telemetry.attach(
        handler,
        [:glific, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if query =~ ~s(FROM "contact_identities"), do: send(test_pid, :identities_query)
        end,
        nil
      )

      assert {:ok, _query_data} = list_identities(user)
      :telemetry.detach(handler)

      assert_received :identities_query
      refute_received :identities_query
    end
  end

  describe "optinContact on the web channel" do
    defp web_optin(user, attrs),
      do:
        auth_query_gql_by(:optin_contact, user,
          variables: Map.merge(%{"channel" => "WEB", "identifier" => "Ravi_12"}, attrs)
        )

    test "opts in the web identity, creating the contact, and leaves WhatsApp consent alone",
         %{manager: user} do
      with_web_channel(fn ->
        {:ok, query_data} = web_optin(user, %{"name" => "Ravi"})

        assert nil == get_in(query_data, [:data, "optinContact", "errors"])
        contact = get_in(query_data, [:data, "optinContact", "contact"])
        assert %{"name" => "Ravi", "optinTime" => nil} = contact

        identity = Repo.get_by!(ContactIdentity, channel: :web, identifier: "ravi_12")
        assert %{optin_status: true, optin_method: "API"} = identity
        assert identity.contact_id == String.to_integer(contact["id"])
      end)
    end

    test "a repeat succeeds on the same contact and identity", %{manager: user} do
      with_web_channel(fn ->
        {:ok, first} = web_optin(user, %{})
        {:ok, second} = web_optin(user, %{})

        assert nil == get_in(second, [:data, "optinContact", "errors"])

        assert get_in(first, [:data, "optinContact", "contact", "id"]) ==
                 get_in(second, [:data, "optinContact", "contact", "id"])

        assert [%{optin_status: true, optin_method: "API"}] =
                 Repo.all(
                   from(i in ContactIdentity,
                     where: i.channel == :web and i.identifier == "ravi_12"
                   )
                 )
      end)
    end

    test "requires an identifier", %{manager: user} do
      with_web_channel(fn ->
        {:ok, query_data} =
          auth_query_gql_by(:optin_contact, user, variables: %{"channel" => "WEB"})

        assert [%{"key" => "Identifier"}] = get_in(query_data, [:data, "optinContact", "errors"])
      end)
    end

    test "is refused while the web channel is off", %{manager: user} do
      {:ok, query_data} = web_optin(user, %{})

      assert [%{"message" => message}] = get_in(query_data, [:data, "optinContact", "errors"])
      assert message =~ "not enabled"
      assert nil == Repo.get_by(ContactIdentity, channel: :web, identifier: "ravi_12")
    end
  end
end
