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

  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_identities/create.gql")
  load_gql(:by_identity, GlificWeb.Schema, "assets/gql/contact_identities/by_identity.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/contact_identities/list.gql")

  setup do
    WebChannelFlagHelpers.reset_web_channel_flag(1)
    :ok
  end

  defp with_web_channel(fun),
    do: WebChannelFlagHelpers.with_web_channel_enabled(1, fun)

  defp input(attrs), do: %{"input" => Map.merge(%{"identifier" => "ravi_12"}, attrs)}

  test "a manager creates a contact for a web identifier", %{manager: user} do
    with_web_channel(fn ->
      assert {:ok, query_data} =
               auth_query_gql_by(:create, user, variables: input(%{"name" => "Ravi"}))

      assert %{
               "id" => contact_id,
               "name" => "Ravi",
               "identities" => [%{"channel" => "WEB", "identifier" => "ravi_12"}]
             } =
               get_in(query_data, [:data, "createContactWithIdentity", "contact"])

      assert %{contact_id: id} =
               Repo.get_by!(ContactIdentity, %{channel: :web, identifier: "ravi_12"})

      assert to_string(id) == contact_id
    end)
  end

  test "repeating the call returns the same contact", %{manager: user} do
    with_web_channel(fn ->
      {:ok, first} = auth_query_gql_by(:create, user, variables: input(%{}))
      {:ok, second} = auth_query_gql_by(:create, user, variables: input(%{}))

      path = [:data, "createContactWithIdentity", "contact", "id"]
      assert get_in(first, path) == get_in(second, path)

      assert 1 ==
               ContactIdentity |> where([i], i.identifier == "ravi_12") |> Repo.aggregate(:count)
    end)
  end

  test "a phone of an existing contact links to it", %{manager: user} do
    with_web_channel(fn ->
      contact = Fixtures.contact_fixture(%{phone: "919876500456"})

      {:ok, query_data} =
        auth_query_gql_by(:create, user, variables: input(%{"phone" => "+91 98765 00456"}))

      assert get_in(query_data, [:data, "createContactWithIdentity", "contact", "id"]) ==
               to_string(contact.id)
    end)
  end

  test "an identifier longer than 255 characters is refused", %{manager: user} do
    with_web_channel(fn ->
      {:ok, query_data} =
        auth_query_gql_by(:create, user,
          variables: input(%{"identifier" => String.duplicate("a", 256)})
        )

      assert [%{"key" => "Identifier", "message" => message}] =
               get_in(query_data, [:data, "createContactWithIdentity", "errors"])

      assert message =~ "1 to 255"
    end)
  end

  test "is refused while the web channel is off", %{manager: user} do
    assert {:ok, query_data} = auth_query_gql_by(:create, user, variables: input(%{}))

    assert [%{"message" => message}] =
             get_in(query_data, [:data, "createContactWithIdentity", "errors"])

    assert message =~ "not enabled"
    assert nil == Repo.get_by(ContactIdentity, %{identifier: "ravi_12"})
  end

  test "a staff user is refused", %{staff: user} do
    with_web_channel(fn ->
      assert {:ok, query_data} = auth_query_gql_by(:create, user, variables: input(%{}))

      assert [%{message: "Unauthorized"}] = query_data.errors
      assert nil == Repo.get_by(ContactIdentity, %{identifier: "ravi_12"})
    end)
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
end
