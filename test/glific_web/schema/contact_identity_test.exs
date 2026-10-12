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

  setup do
    WebChannelFlagHelpers.reset_web_channel_flag(1)
    :ok
  end

  defp with_login_enabled(fun),
    do: WebChannelFlagHelpers.with_web_channel_login_enabled(1, %{}, fun)

  defp input(attrs), do: %{"input" => Map.merge(%{"identifier" => "ravi_12"}, attrs)}

  test "a manager creates a contact for a web identifier", %{manager: user} do
    with_login_enabled(fn ->
      assert {:ok, query_data} =
               auth_query_gql_by(:create, user, variables: input(%{"name" => "Ravi"}))

      assert %{"id" => contact_id, "name" => "Ravi", "phone" => nil} =
               get_in(query_data, [:data, "createContactWithIdentity", "contact"])

      assert %{contact_id: id} =
               Repo.get_by!(ContactIdentity, %{kind: "ngo_username", identifier: "ravi_12"})

      assert to_string(id) == contact_id
    end)
  end

  test "repeating the call returns the same contact", %{manager: user} do
    with_login_enabled(fn ->
      {:ok, first} = auth_query_gql_by(:create, user, variables: input(%{}))
      {:ok, second} = auth_query_gql_by(:create, user, variables: input(%{}))

      path = [:data, "createContactWithIdentity", "contact", "id"]
      assert get_in(first, path) == get_in(second, path)

      assert 1 ==
               ContactIdentity |> where([i], i.identifier == "ravi_12") |> Repo.aggregate(:count)
    end)
  end

  test "a phone of an existing contact links to it", %{manager: user} do
    with_login_enabled(fn ->
      contact = Fixtures.contact_fixture(%{phone: "919876500456"})

      {:ok, query_data} =
        auth_query_gql_by(:create, user, variables: input(%{"phone" => "+91 98765 00456"}))

      assert get_in(query_data, [:data, "createContactWithIdentity", "contact", "id"]) ==
               to_string(contact.id)
    end)
  end

  test "an identifier longer than 255 characters is refused", %{manager: user} do
    with_login_enabled(fn ->
      {:ok, query_data} =
        auth_query_gql_by(:create, user,
          variables: input(%{"identifier" => String.duplicate("a", 256)})
        )

      assert [%{"key" => "Identifier", "message" => message}] =
               get_in(query_data, [:data, "createContactWithIdentity", "errors"])

      assert message =~ "1 to 255"
    end)
  end

  test "is refused while the login flag is off", %{manager: user} do
    assert {:ok, query_data} = auth_query_gql_by(:create, user, variables: input(%{}))

    assert [%{"message" => message}] =
             get_in(query_data, [:data, "createContactWithIdentity", "errors"])

    assert message =~ "not enabled"
    assert nil == Repo.get_by(ContactIdentity, %{identifier: "ravi_12"})
  end

  test "a staff user is refused", %{staff: user} do
    with_login_enabled(fn ->
      assert {:ok, query_data} = auth_query_gql_by(:create, user, variables: input(%{}))

      assert [%{message: "Unauthorized"}] = query_data.errors
      assert nil == Repo.get_by(ContactIdentity, %{identifier: "ravi_12"})
    end)
  end
end
