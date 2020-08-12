defmodule GlificWeb.Schema.ConversationTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Repo,
    Seeds.SeedsDev,
    Messages.Message
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/conversations/list.gql")
  load_gql(:by_contact_id, GlificWeb.Schema, "assets/gql/conversations/by_contact_id.gql")

  test "conversations always returns a few threads" do
    {:ok, result} =
      query_gql_by(:list,
        variables: %{"contactOpts" => %{"limit" => 1}, "messageOpts" => %{"limit" => 3}, "filter" => %{}}
      )

    assert get_in(result, [:data, "search"]) |> length >= 1

    contact_id = get_in(result, [:data, "search", Access.at(0), "contact", "id"])

    {:ok, result} =
      query_gql_by(:list,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"id" => contact_id}
        }
      )

    assert get_in(result, [:data, "search"]) |> length == 1
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

    assert get_in(result, [:data, "search"]) == nil

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

    assert get_in(result, [:data, "search"]) |> length == 1
    assert get_in(result, [:data, "search", Access.at(0), "contact", "id"]) == cid
    assert get_in(result, [:data, "search", Access.at(0), "messages"]) == []
  end

  test "conversation by id" do
    # lets create a new contact with no message
    {:ok, contact} =
      Contacts.create_contact(%{name: "My conversation contact", phone: "+123456789"})

    cid = Integer.to_string(contact.id)

    {:ok, result} =
      query_gql_by(:list,
        variables: %{"messageOpts" => %{"limit" => 1}, "filter" => %{"id" => cid}, "contactOpts" => %{"limit" => 1}}
      )

    assert get_in(result, [:data, "search"]) != nil
    assert get_in(result, [:data, "search", Access.at(0), "contact", "id"]) == cid
    assert get_in(result, [:data, "search", Access.at(0), "messages"]) == []

    # if we send in an invalid id, we should get nil

    {:ok, result} =
      query_gql_by(:by_contact_id,
        variables: %{
          "messageOpts" => %{"limit" => 3},
          "filter" => %{"id" => "234567893453" }
        }
      )

    assert get_in(result, [:data, "search"]) == nil
  end

  test "conversation by ids" do
    # lets create a new contact with no message
    Contacts.create_contact(%{name: "My conversation contact", phone: "+123456789"})

    contact_ids =
      from(c in Message, select: c.contact_id)
      |> Repo.all()
      |> Enum.map(&Integer.to_string(&1))
      |> Enum.uniq

    {:ok, result} =
      query_gql_by(:list,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"ids" => contact_ids}
        }
      )

    IO.inspect(result)

    assert get_in(result, [:data, "search"]) |> length == length(contact_ids)
    assert get_in(result, [:data, "search", Access.at(0), "contact", "id"]) in contact_ids
  end
end
