defmodule GlificWeb.Schema.SearchTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
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

  defp get_saved_search_list(org_id) do
    Searches.list_saved_searches(%{filter: %{organization_id: org_id}})
  end

  defp get_contacts_count(org_id) do
    Contacts.count_contacts(%{filter: %{organization_id: org_id}})
  end

  test "savedSearches field returns list of searches", %{staff: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result
    saved_searches = get_in(query_data, [:data, "savedSearches"])
    assert length(saved_searches) > 0
    [saved_search | _] = saved_searches
    assert get_in(saved_search, ["label"]) != nil
  end

  test "count returns the number of savedSearches", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countSavedSearches"]) >= 5

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"label" => "This tag should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countSavedSearches"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"label" => "Conversations read but not replied"}}
      )

    assert get_in(query_data, [:data, "countSavedSearches"]) == 1
  end

  test "savedSearch id returns one saved search or nil", %{staff: user} do
    [saved_search | _tail] = get_saved_search_list(user.organization_id)

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result

    assert saved_search.label ==
             get_in(query_data, [:data, "savedSearch", "savedSearch", "label"])

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "savedSearch", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "save a search and test possible scenarios and errors", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
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
      auth_query_gql_by(:create, user,
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

  test "update a saved search and test possible scenarios and errors", %{manager: user} do
    [saved_search, saved_search2 | _tail] = get_saved_search_list(user.organization_id)

    result =
      auth_query_gql_by(:update, user,
        variables: %{"id" => saved_search.id, "input" => %{"label" => "New Test Search Label"}}
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateSavedSearch", "savedSearch", "label"])
    assert label == "New Test Search Label"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => saved_search.id,
          "input" => %{"shortcode" => saved_search2.shortcode}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateSavedSearch", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a saved search", %{manager: user} do
    [saved_search | _tail] = get_saved_search_list(user.organization_id)

    result = auth_query_gql_by(:delete, user, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteSavedSearch", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteSavedSearch", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "search for conversations", %{staff: user} do
    {:ok, receiver} =
      Repo.fetch_by(Contact, %{name: "Default receiver", organization_id: user.organization_id})

    receiver_id = to_string(receiver.id)

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => ""},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    # we are just asseting that we got back one contact and it has a valid id
    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) != 0

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => "Default receiver"},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) == receiver_id

    result =
      auth_query_gql_by(:search, user,
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
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => ""},
          "contactOpts" => %{"limit" => get_contacts_count(user.organization_id) * 10},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    # search excludes the org contact id since that is the sender of all messages
    # we need to excluse four contacts,
    # one is the glific admin and the others are the test users: admin, manager, staff contacts
    # we created to emulate the user
    assert length(get_in(query_data, [:data, "search"])) ==
             get_contacts_count(user.organization_id) - 4
  end

  test "save search will save the arguments", %{staff: user} do
    result =
      auth_query_gql_by(:search, user,
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

    assert {:ok, saved_search} =
             Repo.fetch_by(SavedSearch, %{
               label: "Save with Search",
               organization_id: user.organization_id
             })
  end

  test "search for not replied tagged messages in conversations", %{staff: user} do
    {:ok, receiver} =
      Repo.fetch_by(Contact, %{name: "Glific Admin", organization_id: user.organization_id})

    {:ok, sender} =
      Repo.fetch_by(Contact, %{name: "Default receiver", organization_id: user.organization_id})

    {:ok, not_replied_tag} =
      Repo.fetch_by(Tag, %{shortcode: "notreplied", organization_id: user.organization_id})

    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{
        label: "Conversations read but not replied",
        organization_id: user.organization_id
      })

    {:ok, message} =
      %{
        body: saved_search.args["term"],
        flow: :inbound,
        type: :text,
        sender_id: sender.id,
        receiver_id: receiver.id,
        organization_id: receiver.organization_id
      }
      |> Messages.create_message()

    MessageTags.update_message_tags(%{
      message_id: message.id,
      add_tag_ids: [not_replied_tag.id],
      delete_tag_ids: []
    })

    result = auth_query_gql_by(:search, user, variables: saved_search.args)

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) ==
             to_string(sender.id)

    tags = get_in(query_data, [:data, "search", Access.at(0), "messages", Access.at(0), "tags"])

    assert %{"label" => "Not replied"} in tags
  end

  test "search for not responded tagged messages in conversations", %{staff: user} do
    # {:ok, sender} = Repo.fetch_by(Contact, %{name: "Glific Admin"})
    # {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Default receiver"})
    {:ok, not_responded_tag} =
      Repo.fetch_by(Tag, %{shortcode: "notresponded", organization_id: user.organization_id})

    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{
        label: "Conversations read but not responded",
        organization_id: user.organization_id
      })

    message = Fixtures.message_fixture(%{body: saved_search.args["term"]})

    MessageTags.update_message_tags(%{
      message_id: message.id,
      add_tag_ids: [not_responded_tag.id],
      delete_tag_ids: []
    })

    result = auth_query_gql_by(:search, user, variables: saved_search.args)

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) != nil

    tags = get_in(query_data, [:data, "search", Access.at(0), "messages", Access.at(0), "tags"])

    assert %{"label" => "Not Responded"} in tags
  end

  test "search and count for not replied tagged messages in conversations via a created saved search",
       %{staff: user} do
    # {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Glific Admin"})
    # {:ok, sender} = Repo.fetch_by(Contact, %{name: "Default receiver"})
    {:ok, not_replied_tag} =
      Repo.fetch_by(Tag, %{shortcode: "notreplied", organization_id: user.organization_id})

    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{
        label: "Conversations read but not replied",
        organization_id: user.organization_id
      })

    message = Fixtures.message_fixture(%{body: saved_search.args["term"]})

    MessageTags.update_message_tags(%{
      message_id: message.id,
      add_tag_ids: [not_replied_tag.id],
      delete_tag_ids: []
    })

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"savedSearchId" => saved_search.id},
          "contactOpts" => %{},
          "messageOpts" => %{}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) != nil

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"savedSearchId" => saved_search.id, "term" => "defa"},
          "contactOpts" => %{},
          "messageOpts" => %{}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) != nil

    result = auth_query_gql_by(:search_count, user, variables: %{"id" => saved_search.id})

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "savedSearchCount"]) == 1
  end

  # Let's test some of the essential search queries for the conversation

  test "conversations always returns a few threads", %{staff: user} do
    {:ok, result} =
      auth_query_gql_by(:search, user,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 3},
          "filter" => %{}
        }
      )

    assert get_in(result, [:data, "search"]) |> length >= 1

    contact_id = get_in(result, [:data, "search", Access.at(0), "contact", "id"])

    {:ok, result} =
      auth_query_gql_by(:search, user,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"id" => contact_id}
        }
      )

    assert get_in(result, [:data, "search"]) |> length == 1
  end

  test "conversations filtered by a contact id", %{staff: user} do
    # if we send in an invalid id, we should not see any conversations
    {:ok, result} =
      auth_query_gql_by(:search,
        variables: %{
          "contactOpts" => %{"limit" => 3},
          "messageOpts" => %{"limit" => 3},
          "filter" => %{"Gid" => "234567893453"}
        }
      )

    assert get_in(result, [:data, "search"]) == nil

    # lets create a new contact with no message
    contact = Fixtures.contact_fixture()

    cid = Integer.to_string(contact.id)

    {:ok, result} =
      auth_query_gql_by(:search, user,
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

  test "conversation by id", %{staff: user} do
    # lets create a new contact with no message
    contact = Fixtures.contact_fixture()

    cid = Integer.to_string(contact.id)

    {:ok, result} =
      auth_query_gql_by(:search, user,
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
      auth_query_gql_by(:search, user,
        variables: %{
          "messageOpts" => %{"limit" => 3},
          "filter" => %{"id" => "234567893453"}
        }
      )

    assert get_in(result, [:data, "search"]) == nil
  end

  test "conversation by ids", %{staff: user} do
    # lets create a new contact with no message
    Contacts.create_contact(%{
      name: "My conversation contact",
      phone: "+123456789",
      organization_id: user.organization_id
    })

    contact_ids =
      from(c in Message, select: c.contact_id)
      |> Repo.all()
      |> Enum.map(&Integer.to_string(&1))
      |> Enum.uniq()

    {:ok, result} =
      auth_query_gql_by(:search, user,
        variables: %{
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1},
          "filter" => %{"ids" => contact_ids}
        }
      )

    assert get_in(result, [:data, "search"]) |> length == length(contact_ids)
    assert get_in(result, [:data, "search", Access.at(0), "contact", "id"]) in contact_ids
  end

  test "search with the empty tag filter will return the conversation", %{staff: user} do
    {:ok, receiver} =
      Repo.fetch_by(Contact, %{name: "Default receiver", organization_id: user.organization_id})

    receiver_id = to_string(receiver.id)

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => "Def", "includeTags" => []},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) == receiver_id
  end

  test "search with the empty group filter will return the conversation", %{staff: user} do
    {:ok, receiver} =
      Repo.fetch_by(Contact, %{name: "Default receiver", organization_id: user.organization_id})

    receiver_id = to_string(receiver.id)

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => "Def", "includeGroups" => []},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) == receiver_id
  end

  test "search with the group filters will return the conversation", %{staff: user} do
    message = Fixtures.message_fixture()

    contact_group =
      Fixtures.contact_group_fixture(%{
        organization_id: user.organization_id,
        contact_id: message.contact_id
      })

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => "", "includeGroups" => ["#{contact_group.group_id}"]},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) ==
             "#{contact_group.contact_id}"
  end

  test "search with the date range filters will returns the conversations", %{staff: user} do
    message =
      Fixtures.message_fixture()
      |> Repo.preload([:contact])

    contact_count = Contacts.count_contacts(%{filter: %{organization_id: user.organization_id}})

    {:ok, contact} =
      Contacts.update_contact(
        message.contact,
        %{last_message_at: DateTime.utc_now()}
      )

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateRange" => %{
              "from" =>
                DateTime.utc_now() |> DateTime.to_date() |> Date.add(-2) |> Date.to_string(),
              "to" => DateTime.utc_now() |> DateTime.to_date() |> Date.to_string()
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    conatct_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{contact.id}" in conatct_ids

    # it should return empty list if date range doesn't have any messages
    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateRange" => %{
              "from" =>
                DateTime.utc_now() |> DateTime.to_date() |> Date.add(-2) |> Date.to_string(),
              "to" => DateTime.utc_now() |> DateTime.to_date() |> Date.add(-1) |> Date.to_string()
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search"]) == []
  end

  test "search with incomplete date range filters will return the conversations", %{staff: user} do
    message =
      Fixtures.message_fixture()
      |> Repo.preload([:contact])

    contact_count = Contacts.count_contacts(%{filter: %{organization_id: user.organization_id}})

    {:ok, contact} =
      Contacts.update_contact(
        message.contact,
        %{last_message_at: DateTime.utc_now()}
      )

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateRange" => %{
              "from" => nil,
              "to" => nil
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    conatct_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{contact.id}" in conatct_ids

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateRange" => %{
              "from" =>
                DateTime.utc_now() |> DateTime.to_date() |> Date.add(-2) |> Date.to_string()
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    conatct_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{contact.id}" in conatct_ids

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateRange" => %{
              "to" => DateTime.utc_now() |> DateTime.to_date() |> Date.to_string()
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    conatct_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{contact.id}" in conatct_ids
  end
end
