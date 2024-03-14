defmodule GlificWeb.Schema.WaSearchTest do
  alias Glific.Conversations.WAConversation
  alias Glific.WAGroup.WAManagedPhone
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Seeds.SeedsDev,
    Groups.WAGroups,
    WAManagedPhones
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_wa_managed_phones()
    SeedsDev.seed_wa_groups()
    SeedsDev.seed_wa_messages()
    :ok
  end

  load_gql(:wa_search, GlificWeb.Schema, "assets/gql/searches/wa_search.gql")

  test "wa_search for conversations", %{staff: user} do
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{"limit" => 10},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    assert Enum.count(searches) == 3

    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{"limit" => 2},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    assert Enum.count(searches) == 2

    # without group limit
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [conv | _] = searches
    assert Enum.count(searches) == 3
    assert Enum.count(conv["messages"]) in [1, 0]

    # group with no messages should also be in the result
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 10},
          "filter" => %{}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [_conv | _] = searches
    assert Enum.count(searches) == 3
  end

  test "wa_search, ignoring dms", %{staff: user} do
    # Out of 4 messages we seeded, one is DM, so the total messages should be 3
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 10},
          "filter" => %{}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [_conv | _] = searches
    assert Enum.count(searches) == 3
    assert calculate_total_messages(searches) == 3
  end

  test "wa_search with group filter ids", %{staff: user} = attrs do
    [wa_managed_phone_1 | _wa_managed_phones] =
      WAManagedPhones.list_wa_managed_phones(%{organization_id: attrs.organization_id})

    [wa_group_1, wa_group_2] = WAGroups.list_wa_groups(%{organization_id: attrs.organization_id})

    # with available id filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{"id" => to_string(wa_group_1.id)}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    assert Enum.count(searches) == 1

    # # without available id filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{"id" => to_string(123_456)}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    assert Enum.empty?(searches)

    # # with available id list filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{"ids" => [to_string(wa_group_1.id), to_string(wa_group_2.id)]}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [conv | _] = searches
    assert Enum.count(searches) == 2
    assert Enum.count(conv["messages"]) == 1

    # with available phone_id filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 10},
          "filter" => %{"wa_phone_ids" => [to_string(wa_managed_phone_1.id)]}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    # wa_phone_id_1 messages are in wa_group_1 and wa_phone_id2 messsages are in wa_group_2
    # So we expect search count to be 1, since only 1 wa_group will be returned
    assert Enum.count(searches) == 1
    # with id and wa_phone_id filter
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 10},
          "filter" => %{
            "id" => to_string(wa_group_1.id),
            "wa_phone_ids" => [to_string(wa_managed_phone_1.id)]
          }
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    assert Enum.count(searches) == 1

    # # with search group and group label filter
    group =
      Fixtures.group_fixture(%{organization_id: user.organization_id})
      |> Map.put(:group_type, "WA")

    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "filter" => %{
            "groupLabel" => "#{group.label}",
            "searchGroup" => true
          },
          "waGroupOpts" => %{"limit" => 1},
          "waMessageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, %{data: %{"search" => _searches}}} = result

    # with search group filter
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "filter" => %{
            "searchGroup" => true
          },
          "waGroupOpts" => %{"limit" => 1},
          "waMessageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, %{data: %{"search" => _searches}}} = result
  end

  @spec calculate_total_messages([WAConversation.t()]) :: non_neg_integer()
  defp calculate_total_messages(searches) do
    Enum.reduce(searches, 0, fn conv, count ->
      count + Enum.count(conv["messages"])
    end)
  end
end
