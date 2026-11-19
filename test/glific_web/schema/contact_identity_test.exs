defmodule GlificWeb.Schema.ContactIdentityTest do
  # Not async: it flips global FunWithFlags flags and writes the organization's credential.
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.ContactIdentity,
    Fixtures,
    Repo,
    WebChannelFlagHelpers
  }

  load_gql(:by_identity, GlificWeb.Schema, "assets/gql/contact_identities/by_identity.gql")
  load_gql(:add, GlificWeb.Schema, "assets/gql/contact_identities/add.gql")
  load_gql(:create_contact, GlificWeb.Schema, "assets/gql/contact_identities/create_contact.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/contact_identities/list.gql")
  load_gql(:channels, GlificWeb.Schema, "assets/gql/contact_identities/channels.gql")
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

  describe "channels on a contact (#5877)" do
    defp channels_of(user, contact) do
      {:ok, query_data} =
        auth_query_gql_by(:channels, user,
          variables: %{"filter" => %{}, "opts" => %{"limit" => 1000}}
        )

      query_data
      |> get_in([:data, "contacts"])
      |> Enum.find(&(&1["id"] == to_string(contact.id)))
      |> Map.fetch!("channels")
    end

    test "a web-only contact has Web only, with no activity before its first message", %{
      staff: user
    } do
      contact = Fixtures.contact_without_phone_fixture()
      Fixtures.contact_identity_fixture(%{contact_id: contact.id, identifier: "ravi_12"})

      assert [%{"channel" => "WEB", "lastMessageAt" => nil}] = channels_of(user, contact)
    end

    test "a contact on both channels has each with its own last message, WhatsApp first, and staff see it",
         %{staff: user} do
      contact =
        Fixtures.contact_fixture(%{
          phone: "91" <> to_string(8_000_000_000 + System.unique_integer([:positive]))
        })

      {:ok, _contact} = Contacts.add_identity(contact, :web, "ravi_web")

      web_time = ~U[2026-11-01 10:00:00Z]
      whatsapp_time = ~U[2026-11-02 10:00:00Z]

      ContactIdentity
      |> where([i], i.contact_id == ^contact.id and i.channel == :web)
      |> Repo.update_all(set: [last_message_at: web_time])

      ContactIdentity
      |> where([i], i.contact_id == ^contact.id and i.channel == :whatsapp)
      |> Repo.update_all(set: [last_message_at: whatsapp_time])

      Glific.Contacts.Contact
      |> where([c], c.id == ^contact.id)
      |> Repo.update_all(set: [last_message_at: whatsapp_time])

      assert [
               %{"channel" => "WHATSAPP", "lastMessageAt" => whatsapp},
               %{"channel" => "WEB", "lastMessageAt" => web}
             ] = channels_of(user, contact)

      assert {:ok, ^whatsapp_time, _} = DateTime.from_iso8601(whatsapp)
      assert {:ok, ^web_time, _} = DateTime.from_iso8601(web)
    end

    test "a contact with two WhatsApp identities is reported and still gets the latest time", %{
      staff: user
    } do
      contact =
        Fixtures.contact_fixture(%{
          phone: "91" <> to_string(8_300_000_000 + System.unique_integer([:positive]))
        })

      later = ~U[2026-11-05 10:00:00Z]

      ContactIdentity
      |> where([i], i.contact_id == ^contact.id and i.channel == :whatsapp)
      |> Repo.update_all(set: [last_message_at: ~U[2026-11-01 10:00:00Z]])

      # The data bug this guards against: a second WhatsApp row for the same contact.
      Repo.insert!(%ContactIdentity{
        contact_id: contact.id,
        organization_id: contact.organization_id,
        channel: :whatsapp,
        identifier: "91" <> to_string(8_400_000_000 + System.unique_integer([:positive])),
        last_message_at: later
      })

      Glific.Contacts.Contact
      |> where([c], c.id == ^contact.id)
      |> Repo.update_all(set: [last_message_at: ~U[2026-11-01 10:00:00Z]])

      level = Logger.level()
      Logger.configure(level: :error)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert [%{"channel" => "WHATSAPP", "lastMessageAt" => whatsapp}] =
                   channels_of(user, contact)

          assert {:ok, ^later, _} = DateTime.from_iso8601(whatsapp)
        end)

      assert log =~ "Contact #{contact.id} has 2 WhatsApp identities"
    end

    test "a WhatsApp contact without an identity row yet falls back to the contact's clock", %{
      staff: user
    } do
      contact =
        Fixtures.contact_fixture(%{
          phone: "91" <> to_string(8_100_000_000 + System.unique_integer([:positive]))
        })

      at = ~U[2026-11-03 10:00:00Z]
      {:ok, contact} = Contacts.update_contact(contact, %{last_message_at: at})
      Repo.delete_all(from(i in ContactIdentity, where: i.contact_id == ^contact.id))

      assert [%{"channel" => "WHATSAPP", "lastMessageAt" => whatsapp}] =
               channels_of(user, contact)

      assert {:ok, ^at, _} = DateTime.from_iso8601(whatsapp)
    end

    test "WhatsApp shows the contact's clock when it is newer than its identity's", %{
      staff: user
    } do
      contact =
        Fixtures.contact_fixture(%{
          phone: "91" <> to_string(8_200_000_000 + System.unique_integer([:positive]))
        })

      identity_time = ~U[2026-11-01 10:00:00Z]
      contact_time = ~U[2026-11-04 10:00:00Z]

      # Written directly: update_contact/2 would carry the contact's clock onto the identity.
      ContactIdentity
      |> where([i], i.contact_id == ^contact.id and i.channel == :whatsapp)
      |> Repo.update_all(set: [last_message_at: identity_time])

      Glific.Contacts.Contact
      |> where([c], c.id == ^contact.id)
      |> Repo.update_all(set: [last_message_at: contact_time])

      assert [%{"channel" => "WHATSAPP", "lastMessageAt" => whatsapp}] =
               channels_of(user, contact)

      assert {:ok, ^contact_time, _} = DateTime.from_iso8601(whatsapp)
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

    test "records the opt-in history event on the web channel", %{manager: user} do
      with_web_channel(fn ->
        {:ok, query_data} = web_optin(user, %{})
        contact_id = get_in(query_data, [:data, "optinContact", "contact", "id"])

        assert [%{channel: :web, event_label: "contact opted in on web, via API"}] =
                 Glific.Contacts.list_contact_history(%{
                   filter: %{contact_id: contact_id, event_type: "contact_opted_in"}
                 })
      end)
    end

    test "WhatsApp without a phone is refused", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:optin_contact, user, variables: %{"name" => "No phone"})

      assert [%{"key" => "phone"}] = get_in(query_data, [:data, "optinContact", "errors"])
    end

    test "an explicit null channel opts in on WhatsApp", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:optin_contact, user,
          variables: %{"channel" => nil, "phone" => "919876500099"}
        )

      assert nil == get_in(query_data, [:data, "optinContact", "errors"])
      assert get_in(query_data, [:data, "optinContact", "contact", "optinTime"])
    end

    test "is refused while the web channel is off", %{manager: user} do
      {:ok, query_data} = web_optin(user, %{})

      assert [%{"message" => message}] = get_in(query_data, [:data, "optinContact", "errors"])
      assert message =~ "not enabled"
      assert nil == Repo.get_by(ContactIdentity, channel: :web, identifier: "ravi_12")
    end
  end
end
