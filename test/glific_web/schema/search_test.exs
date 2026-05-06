defmodule GlificWeb.Schema.SearchTest do
  alias Glific.WAGroup.WAManagedPhone
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Groups.Group,
    Messages,
    Messages.Message,
    Repo,
    RepoReplica,
    Searches,
    Searches.SavedSearch,
    Searches.Search,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    org = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    Fixtures.wa_managed_phone_fixture(%{organization_id: org.id})
    Application.put_env(:glific, Glific.Searches, %{repo_module: RepoReplica})
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
  load_gql(:search_multi, GlificWeb.Schema, "assets/gql/searches/search_multi.gql")
  load_gql(:wa_search_multi, GlificWeb.Schema, "assets/gql/searches/wa_search_multi.gql")

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
    assert message =~ "has already been taken"
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
    assert message =~ "has already been taken"
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

  test "search struct will be generated via embedded schema having contacts and messages",
       _attrs do
    contacts = Contacts.list_contacts(%{})
    messages = Messages.list_messages(%{})
    search = %Search{contacts: contacts, messages: messages}
    assert search.contacts == contacts
    assert search.messages == messages
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

    # we are just asserting that we got back one contact and it has a valid id
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
    # this is no longer true, hence removing the -1
    assert length(get_in(query_data, [:data, "search"])) ==
             get_contacts_count(user.organization_id)
  end

  test "search for conversations group", %{staff: user} = attrs do
    [cg1 | _] = Fixtures.group_contacts_fixture(attrs)
    {:ok, group} = Repo.fetch_by(Group, %{id: cg1.group_id})

    valid_attrs = %{
      body: "#{group.label} message",
      flow: :outbound,
      type: :text,
      organization_id: attrs.organization_id
    }

    Messages.create_and_send_message_to_group(valid_attrs, group, :session)

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => "", "searchGroup" => true, "include_groups" => ["#{group.id}"]},
          "contactOpts" => %{"limit" => 10},
          "messageOpts" => %{"limit" => 10}
        }
      )

    assert {:ok, query_data} = result
    assert [conversation] = get_in(query_data, [:data, "search"])
    assert %{"body" => "#{group.label} message"} in conversation["group"]["messages"]
  end

  test "search for conversations group with group label", %{staff: user} = attrs do
    [cg1 | _] = Fixtures.group_contacts_fixture(attrs)
    {:ok, group} = Repo.fetch_by(Group, %{id: cg1.group_id})

    valid_attrs = %{
      body: "#{group.label} message",
      flow: :outbound,
      type: :text,
      organization_id: attrs.organization_id
    }

    Messages.create_and_send_message_to_group(valid_attrs, group, :session)

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "groupLabel" => "#{group.label}",
            "searchGroup" => true
          },
          "contactOpts" => %{"limit" => 10},
          "messageOpts" => %{"limit" => 10}
        }
      )

    assert {:ok, query_data} = result
    assert [conversation] = get_in(query_data, [:data, "search"])
    assert %{"body" => "#{group.label} message"} in conversation["group"]["messages"]
    assert conversation["group"]["label"] == group.label
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

    assert {:ok, _query_data} = result

    assert {:ok, _saved_search} =
             Repo.fetch_by(SavedSearch, %{
               label: "Save with Search",
               organization_id: user.organization_id
             })
  end

  test "search for not replied tagged messages in conversations", %{staff: user} do
    {:ok, receiver} =
      Repo.fetch_by(Contact, %{name: "Default receiver", organization_id: user.organization_id})

    sender = Fixtures.contact_fixture()

    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{
        label: "Conversations read but not replied",
        organization_id: user.organization_id
      })

    {:ok, _message} =
      %{
        body: saved_search.args["term"],
        flow: :inbound,
        type: :text,
        sender_id: sender.id,
        receiver_id: receiver.id,
        organization_id: receiver.organization_id
      }
      |> Messages.create_message()

    result =
      auth_query_gql_by(:search, user,
        variables: put_in(saved_search.args, ["filter", "id"], to_string(sender.id))
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) ==
             to_string(sender.id)

    is_replied = get_in(query_data, [:data, "search", Access.at(0), "contact", "isOrgReplied"])

    assert is_replied == false
  end

  test "search for not responded tagged messages in conversations", %{staff: user} do
    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{
        label: "Conversations read but not responded",
        organization_id: user.organization_id
      })

    message = Fixtures.message_fixture(%{body: saved_search.args["term"]})

    result =
      auth_query_gql_by(:search, user,
        variables: put_in(saved_search.args, ["filter", "id"], to_string(message.contact_id))
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) != nil

    is_replied = get_in(query_data, [:data, "search", Access.at(0), "contact", "isOrgReplied"])

    assert is_replied == false
  end

  test "search and count for not replied tagged messages in conversations via a created saved search",
       %{staff: user} do
    {:ok, saved_search} =
      Repo.fetch_by(SavedSearch, %{
        label: "Conversations read but not replied",
        organization_id: user.organization_id
      })

    message = Fixtures.message_fixture(%{body: saved_search.args["term"]})

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"savedSearchId" => saved_search.id, "id" => to_string(message.contact_id)},
          "contactOpts" => %{},
          "messageOpts" => %{}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) != nil

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "savedSearchId" => saved_search.id,
            "term" => "defa",
            "id" => to_string(message.contact_id)
          },
          "contactOpts" => %{},
          "messageOpts" => %{}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) != nil

    result = auth_query_gql_by(:search_count, user, variables: %{"id" => saved_search.id})

    assert {:ok, query_data} = result
    # we don't know how many exist from the seed data
    assert get_in(query_data, [:data, "savedSearchCount"]) > 1
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
      auth_query_gql_by(:search, user,
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

  test "search contacts field obeys label filters", %{staff: user} do
    flow_label = Fixtures.flow_label_fixture(%{organization_id: user.organization_id})

    last_message =
      Message
      |> Ecto.Query.last()
      |> Repo.one()

    Repo.get(Message, last_message.id)
    |> Message.changeset(%{flow_label: flow_label.name})
    |> Repo.update()

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"includeLabels" => ["#{flow_label.id}"]},
          "contactOpts" => %{"limit" => 25},
          "messageOpts" => %{"limit" => 25}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "search", Access.at(0), "messages", Access.at(0), "body"]) ==
             last_message.body
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

  test "search with the empty user filter will return the conversation", %{staff: user} do
    {:ok, receiver} =
      Repo.fetch_by(Contact, %{name: "Default receiver", organization_id: user.organization_id})

    receiver_id = to_string(receiver.id)

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => "Def", "includeUsers" => []},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "search", Access.at(0), "contact", "id"]) == receiver_id
  end

  test "search with the user filters will return the conversation", %{staff: user} do
    _message = Fixtures.message_fixture(%{user_id: user.id})

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{"term" => "", "includeUsers" => ["#{user.id}"]},
          # need a fix, for now need to keep contact opts as 10
          "contactOpts" => %{"limit" => 10},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    messages = get_in(query_data, [:data, "search", Access.at(0), "messages"])
    assert messages != []
    assert get_in(messages, [Access.at(0), "user", "id"]) == "#{user.id}"
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
              "from" => DateTime.utc_now() |> DateTime.add(-2, :hour) |> Date.to_iso8601(),
              "to" => DateTime.utc_now() |> Date.to_iso8601()
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    contact_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{contact.id}" in contact_ids

    # it should return empty list if date range doesn't have any messages
    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateRange" => %{
              "from" =>
                DateTime.utc_now()
                |> DateTime.add(-2, :day)
                |> Date.to_iso8601(),
              "to" =>
                DateTime.utc_now()
                |> DateTime.add(-1, :day)
                |> Date.to_iso8601()
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    data =
      Enum.filter(
        query_data[:data]["search"],
        fn row -> row["messages"] != [] end
      )

    assert data == []
  end

  test "search with the date expression filters will returns the conversations", %{staff: user} do
    message =
      Fixtures.message_fixture()
      |> Repo.preload([:contact])

    contact_count = Contacts.count_contacts(%{filter: %{organization_id: user.organization_id}})

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateExpression" => %{
              "fromExpression" => "<%= Timex.shift(Timex.today(), days: -2)",
              "toExpression" => "<%= Timex.today() %>"
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    contact_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{message.contact.id}" in contact_ids
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

    contact_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{contact.id}" in contact_ids

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateRange" => %{
              "from" => DateTime.utc_now() |> DateTime.add(-2, :hour) |> Date.to_iso8601()
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    contact_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{contact.id}" in contact_ids

    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "term" => "",
            "dateRange" => %{
              "to" => DateTime.utc_now() |> Date.to_iso8601()
            }
          },
          "contactOpts" => %{"limit" => contact_count},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    contact_ids =
      Enum.reduce(query_data[:data]["search"], [], fn row, acc ->
        acc ++ [row["contact"]["id"]]
      end)

    assert "#{contact.id}" in contact_ids
  end

  test "Search by term will return the search input", %{staff: user} do
    result =
      auth_query_gql_by(:search_multi, user,
        variables: %{
          "filter" => %{"term" => "Default"},
          "contactOpts" => %{"limit" => 1},
          "messageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result

    contacts = get_in(query_data, [:data, "searchMulti", "contacts"])
    messages = get_in(query_data, [:data, "searchMulti", "messages"])
    assert contacts != []
    assert hd(contacts)["id"] != nil
    assert String.contains?(hd(messages)["contact"]["name"], "Default")
    assert messages != []
  end

  test "WA Search by term will return the search input", %{staff: user} = attrs do
    {:ok, wa_phone} = Repo.fetch_by(WAManagedPhone, %{organization_id: attrs.organization_id})

    wa_group =
      attrs
      |> Map.put(:label, "wa group")
      |> Map.put(:wa_managed_phone_id, wa_phone.id)
      |> Fixtures.wa_group_fixture()

    _wa_message_1 =
      Map.put(attrs, :wa_group_id, wa_group.id) |> Fixtures.wa_message_fixture()

    _message_2 =
      attrs
      |> Map.put(:wa_group_id, wa_group.id)
      |> Map.put(:body, "wa search multi")
      |> Fixtures.wa_message_fixture()

    result =
      auth_query_gql_by(:wa_search_multi, user,
        variables: %{
          "filter" => %{},
          "waGroupOpts" => %{"limit" => 25},
          "waMessageOpts" => %{"limit" => 25}
        }
      )

    assert {:ok, query_data} = result
    wa_messages = get_in(query_data, [:data, "WaSearchMulti", "waMessages"])
    assert length(wa_messages) == 2

    result =
      auth_query_gql_by(:wa_search_multi, user,
        variables: %{
          "filter" => %{"term" => "wa search"},
          "waGroupOpts" => %{"limit" => 1},
          "waMessageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, query_data} = result
    [wa_message] = get_in(query_data, [:data, "WaSearchMulti", "waMessages"])
    assert wa_message["body"] == "wa search multi"
  end

  test "search query with date range filters", %{staff: user} do
    message_dates = [
      ~U[2025-05-15 10:00:00Z],
      ~U[2025-05-20 10:00:00Z],
      ~U[2025-05-25 10:00:00Z]
    ]

    Enum.map(message_dates, fn date ->
      message = Fixtures.message_fixture()

      Repo.update_all(
        from(m in Messages.Message, where: m.id == ^message.id),
        set: [inserted_at: date]
      )
    end)

    # case 1: messages between a date range
    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "dateRange" => %{
              "from" => "2025-05-19",
              "to" => "2025-05-22"
            }
          },
          "contactOpts" => %{"limit" => 10},
          "messageOpts" => %{"limit" => 10}
        }
      )

    assert {:ok, query_data} = result
    contacts = get_in(query_data, [:data, "search"])
    from_date = ~D[2025-05-19]
    to_date = ~D[2025-05-22]

    # ensure all messages are within the date range
    Enum.each(contacts, fn contact ->
      messages = get_in(contact, ["messages"])

      Enum.each(messages, fn message ->
        inserted_at = get_in(message, ["inserted_at"])

        message_date =
          inserted_at
          |> DateTime.from_iso8601()
          |> elem(1)
          |> DateTime.to_date()

        assert Date.compare(message_date, from_date) in [:eq, :gt]
        assert Date.compare(message_date, to_date) in [:eq, :lt]
      end)
    end)

    # case 2: messages after a date
    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "dateRange" => %{
              "from" => "2025-05-22",
              "to" => nil
            }
          },
          "contactOpts" => %{"limit" => 10},
          "messageOpts" => %{"limit" => 10}
        }
      )

    assert {:ok, query_data} = result
    contacts = get_in(query_data, [:data, "search"])
    from_date = ~D[2025-05-22]

    # ensure all messages are after the date
    Enum.each(contacts, fn contact ->
      messages = get_in(contact, ["messages"])

      Enum.each(messages, fn message ->
        inserted_at = get_in(message, ["inserted_at"])

        message_date =
          inserted_at
          |> DateTime.from_iso8601()
          |> elem(1)
          |> DateTime.to_date()

        assert Date.compare(message_date, from_date) in [:eq, :gt]
      end)
    end)

    # case 3: messages before a date
    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "dateRange" => %{
              "from" => nil,
              "to" => "2025-05-17"
            }
          },
          "contactOpts" => %{"limit" => 10},
          "messageOpts" => %{"limit" => 10}
        }
      )

    assert {:ok, query_data} = result
    contacts = get_in(query_data, [:data, "search"])
    to_date = ~D[2025-05-17]

    # ensure all messages are before the date
    Enum.each(contacts, fn contact ->
      messages = get_in(contact, ["messages"])

      Enum.each(messages, fn message ->
        inserted_at = get_in(message, ["inserted_at"])

        message_date =
          inserted_at
          |> DateTime.from_iso8601()
          |> elem(1)
          |> DateTime.to_date()

        assert Date.compare(message_date, to_date) in [:eq, :lt]
      end)
    end)

    # case 4: both dates are same
    result =
      auth_query_gql_by(:search, user,
        variables: %{
          "filter" => %{
            "dateRange" => %{
              "from" => "2025-05-17",
              "to" => "2025-05-17"
            }
          },
          "contactOpts" => %{"limit" => 10},
          "messageOpts" => %{"limit" => 10}
        }
      )

    assert {:ok, query_data} = result
    contacts = get_in(query_data, [:data, "search"])
    to_date = ~D[2025-05-17]

    # ensure all messages are of same date
    Enum.each(contacts, fn contact ->
      messages = get_in(contact, ["messages"])

      Enum.each(messages, fn message ->
        inserted_at = get_in(message, ["inserted_at"])

        message_date =
          inserted_at
          |> DateTime.from_iso8601()
          |> elem(1)
          |> DateTime.to_date()

        assert Date.compare(message_date, to_date) == :eq
      end)
    end)
  end
end
