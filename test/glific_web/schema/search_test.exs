defmodule GlificWeb.Schema.SearchTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Messages,
    Messages.Message,
    Repo,
    Searches,
    Searches.SavedSearch,
    Seeds.SeedsDev,
    Tags.MessageTags,
    Tags.Tag
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/searches/list.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/searches/count.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/searches/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/searches/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/searches/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/searches/delete.gql")
  load_gql(:search, GlificWeb.Schema, "assets/gql/searches/search.gql")
  load_gql(:search_count, GlificWeb.Schema, "assets/gql/searches/search_count.gql")

  test "savedSearches field returns list of searches" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result
    saved_searches = get_in(query_data, [:data, "savedSearches"])
    assert length(saved_searches) > 0
    [saved_search | _] = saved_searches
    assert get_in(saved_search, ["label"]) != nil
  end

  test "count returns the number of savedSearches" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countSavedSearches"]) >= 5

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"label" => "This tag should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countSavedSearches"]) == 0

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"label" => "Conversations read but not replied"}}
      )

    assert get_in(query_data, [:data, "countSavedSearches"]) == 1
  end

  test "savedSearch id returns one saved search or nil" do
    [saved_search | _tail] = Searches.list_saved_searches()

    result = query_gql_by(:by_id, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result

    assert saved_search.label ==
             get_in(query_data, [:data, "savedSearch", "savedSearch", "label"])

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "savedSearch", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "save a search and test possible scenarios and errors" do
    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "label" => "Test search",
            "shortcode" => "test",
            "args" => Jason.encode!(%{term: "Default"})
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createSavedSearch", "savedSearch", "label"])
    assert label == "Test search"

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "label" => "Test search",
            "shortcode" => "test",
            "args" => Jason.encode!(%{term: "Default"})
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createSavedSearch", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update a saved search and test possible scenarios and errors" do
    [saved_search, saved_search2 | _tail] = Searches.list_saved_searches()

    result =
      query_gql_by(:update,
        variables: %{"id" => saved_search.id, "input" => %{"label" => "New Test Search Label"}}
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateSavedSearch", "savedSearch", "label"])
    assert label == "New Test Search Label"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => saved_search.id,
          "input" => %{"shortcode" => saved_search2.shortcode}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateSavedSearch", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a saved search" do
    [saved_search | _tail] = Searches.list_saved_searches()

    result = query_gql_by(:delete, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteSavedSearch", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteSavedSearch", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "search for conversations" do
    {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Default receiver"})

    receiver_id = to_string(receiver.id)

    result =
      query_gql_by(:search,
        variables: %{
          "filter" => %{"term" => ""},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) ==
             receiver_id

    result =
      query_gql_by(:search,
        variables: %{
          "filter" => %{"term" => "Default receiver"},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) == receiver_id

    result =
      query_gql_by(:search,
        variables: %{
          "filter" => %{"term" => "This term is highly unlikely to occur superfragerlicious"},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search"]) == []

    # lets do an empty search
    # should return all contacts
    result =
      query_gql_by(:search,
        variables: %{
          "filter" => %{"term" => ""},
          "contactOpts" => %{"limit" => Contacts.count_contacts()},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    # search excludes the org contact id since that is the sender of all messages
    assert length(get_in(query_data, [:data, "search"])) == Contacts.count_contacts() - 1
  end

  test "save search will save the arguments" do
    result =
      query_gql_by(:search,
        variables: %{
          "saveSearchInput" => %{
            "label" => "Save with Search",
            "shortcode" => "SaveSearch"
          },
          "filter" => %{"term" => "Default"},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    assert {:ok, saved_search} = Repo.fetch_by(SavedSearch, %{label: "Save with Search"})
  end

  test "search for not replied tagged messages in conversations" do
    {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Glific Admin"})
    {:ok, sender} = Repo.fetch_by(Contact, %{name: "Default receiver"})
    {:ok, not_replied_tag} = Repo.fetch_by(Tag, %{shortcode: "notreplied"})

    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{label: "Conversations read but not replied"})

    {:ok, message} =
      %{
        body: saved_search.args["term"],
        flow: :inbound,
        type: :text,
        sender_id: sender.id,
        receiver_id: receiver.id
      }
      |> Messages.create_message()

    MessageTags.update_message_tags(%{
      message_id: message.id,
      add_tag_ids: [not_replied_tag.id],
      delete_tag_ids: []
    })

    result =
      query_gql_by(:search,
        variables: saved_search.args
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) ==
             to_string(sender.id)

    tags = get_in(query_data, [:data, "search", Access.at(0), "messages", Access.at(0), "tags"])

    assert %{"label" => "Not replied"} in tags
  end

  test "search for not responded tagged messages in conversations" do
    {:ok, sender} = Repo.fetch_by(Contact, %{name: "Glific Admin"})
    {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Default receiver"})
    {:ok, not_responded_tag} = Repo.fetch_by(Tag, %{shortcode: "notresponded"})

    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{label: "Conversations read but not responded"})

    {:ok, message} =
      %{
        body: saved_search.args["term"],
        flow: :outbound,
        type: :text,
        sender_id: sender.id,
        receiver_id: receiver.id
      }
      |> Messages.create_message()

    MessageTags.update_message_tags(%{
      message_id: message.id,
      add_tag_ids: [not_responded_tag.id],
      delete_tag_ids: []
    })

    result =
      query_gql_by(:search,
        variables: saved_search.args
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) ==
             to_string(receiver.id)

    tags = get_in(query_data, [:data, "search", Access.at(0), "messages", Access.at(0), "tags"])

    assert %{"label" => "Not Responded"} in tags
  end

  test "search and count for not replied tagged messages in conversations via a created saved search" do
    {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Glific Admin"})
    {:ok, sender} = Repo.fetch_by(Contact, %{name: "Default receiver"})
    {:ok, not_replied_tag} = Repo.fetch_by(Tag, %{shortcode: "notreplied"})

    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{label: "Conversations read but not replied"})

    {:ok, message} =
      %{
        body: saved_search.args["term"],
        flow: :inbound,
        type: :text,
        sender_id: sender.id,
        receiver_id: receiver.id
      }
      |> Messages.create_message()

    MessageTags.update_message_tags(%{
      message_id: message.id,
      add_tag_ids: [not_replied_tag.id],
      delete_tag_ids: []
    })

    result =
      query_gql_by(:search,
        variables: %{
          "filter" => %{"savedSearchId" => saved_search.id},
          "contactOpts" => %{},
          "messageOpts" => %{}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) ==
             to_string(sender.id)

    result =
      query_gql_by(:search,
        variables: %{
          "filter" => %{"savedSearchId" => saved_search.id, "term" => "defa"},
          "contactOpts" => %{},
          "messageOpts" => %{}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) ==
             to_string(sender.id)

    result =
      query_gql_by(:search_count,
        variables: %{"id" => saved_search.id}
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "savedSearchCount"]) == 1
  end

  # Let's test some of the essential search queries for the conversation

  test "conversations always returns a few threads" do
    {:ok, result} =
      query_gql_by(:search,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 3},
          "filter" => %{}
        }
      )

    assert get_in(result, [:data, "search"]) |> length >= 1

    contact_id = get_in(result, [:data, "search", Access.at(0), "contact", "id"])

    {:ok, result} =
      query_gql_by(:search,
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
      query_gql_by(:search,
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
      query_gql_by(:search,
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
      query_gql_by(:search,
        variables: %{
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"id" => cid},
          "contactOpts" => %{"limit" => 1}
        }
      )

    assert get_in(result, [:data, "search"]) != nil
    assert get_in(result, [:data, "search", Access.at(0), "contact", "id"]) == cid
    assert get_in(result, [:data, "search", Access.at(0), "messages"]) == []

    # if we send in an invalid id, we should get nil

    {:ok, result} =
      query_gql_by(:search,
        variables: %{
          "messageOpts" => %{"limit" => 3},
          "filter" => %{"id" => "234567893453"}
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
      |> Enum.uniq()

    {:ok, result} =
      query_gql_by(:search,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"ids" => contact_ids}
        }
      )

    assert get_in(result, [:data, "search"]) |> length == length(contact_ids)
    assert get_in(result, [:data, "search", Access.at(0), "contact", "id"]) in contact_ids
  end

  test "search with the empty tag filter will return the conversation " do
    {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Default receiver"})
    receiver_id = to_string(receiver.id)

    result =
      query_gql_by(:search,
        variables: %{
          "filter" => %{"term" => "Def", "includeTags" => []},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) == receiver_id
  end
end
