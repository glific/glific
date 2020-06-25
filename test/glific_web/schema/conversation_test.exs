defmodule GlificWeb.Schema.ConversationTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.Contacts

  setup do
    lang = Glific.Seeds.seed_language()
    default_provider = Glific.Seeds.seed_providers()
    Glific.Seeds.seed_organizations(default_provider, lang)
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/conversations/list.gql")
  load_gql(:by_contact_id, GlificWeb.Schema, "assets/gql/conversations/by_contact_id.gql")

  test "conversations always returns a few threads" do
    {:ok, result} =
      query_gql_by(:list,
        variables: %{"contactOpts" => %{"limit" => 1}, "messageOpts" => %{"limit" => 3}}
      )

    assert get_in(result, [:data, "conversations"]) |> length >= 1

    contact_id = get_in(result, [:data, "conversations", Access.at(0), "contact", "id"])

    {:ok, result} =
      query_gql_by(:list,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"id" => contact_id}
        }
      )

    assert get_in(result, [:data, "conversations"]) |> length == 1
  end

  test "conversations filtered by a contact id" do
    # if we send in an invalid id, we should not see any conversations
    {:ok, result} =
      query_gql_by(:list,
        variables: %{
          "contactOpts" => %{"limit" => 3},
          "messageOpts" => %{"limit" => 3},
          "filter" => %{"Gid" => "234567893453"}
        }
      )

    assert get_in(result, [:data, "conversations"]) == nil

    # lets create a new contact with no message
    {:ok, contact} =
      Contacts.create_contact(%{name: "My conversation contact", phone: "+123456789"})

    cid = Integer.to_string(contact.id)

    {:ok, result} =
      query_gql_by(:list,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"id" => cid}
        }
      )

    assert get_in(result, [:data, "conversations"]) |> length == 1
    assert get_in(result, [:data, "conversations", Access.at(0), "contact", "id"]) == cid
    assert get_in(result, [:data, "conversations", Access.at(0), "messages"]) == []
  end

  test "conversation by id" do
    # lets create a new contact with no message
    {:ok, contact} =
      Contacts.create_contact(%{name: "My conversation contact", phone: "+123456789"})

    cid = Integer.to_string(contact.id)

    {:ok, result} =
      query_gql_by(:by_contact_id,
        variables: %{"contact_id" => cid, "messageOpts" => %{"limit" => 1}, "filter" => %{}}
      )

    assert get_in(result, [:data, "conversation"]) != nil
    assert get_in(result, [:data, "conversation", "contact", "id"]) == cid
    assert get_in(result, [:data, "conversation", "messages"]) == []

    # if we send in an invalid id, we should get nil
    {:ok, result} =
      query_gql_by(:by_contact_id,
        variables: %{
          "contact_id" => "234567893453",
          "messageOpts" => %{"limit" => 3},
          "filter" => %{}
        }
      )

    assert get_in(result, [:data, "conversation"]) == nil
  end

  test "conversation by ids" do
    # lets create a new contact with no message
    Contacts.create_contact(%{name: "My conversation contact", phone: "+123456789"})

    contact_ids =
      from(c in Contacts.Contact, select: c.id)
      |> Glific.Repo.all()
      |> Enum.map(&Integer.to_string(&1))

    {:ok, result} =
      query_gql_by(:list,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"ids" => contact_ids}
        }
      )

    assert get_in(result, [:data, "conversations"]) |> length == length(contact_ids)
    assert get_in(result, [:data, "conversations", Access.at(0), "contact", "id"]) in contact_ids
  end
end
