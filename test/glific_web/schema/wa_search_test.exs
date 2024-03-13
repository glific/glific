defmodule GlificWeb.Schema.WaSearchTest do
  alias Glific.Conversations.WAConversation
  alias Glific.WAGroup.WAManagedPhone
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Groups.WAGroup,
    Repo,
    Seeds.SeedsDev
  }

  import Ecto.Query

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

  @tag :skip
  test "wa_search with group filter ids", %{staff: user} do
    [id1, id2, _id3] =
      WAGroup
      |> where([grp], grp.organization_id == 1)
      |> select([grp], grp.id)
      |> Repo.all()

    [wa_id1, _wa_id2, _] =
      WAManagedPhone
      |> where([ph], ph.organization_id == 1)
      |> select([ph], ph.id)
      |> Repo.all()

    # with available id filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{"id" => to_string(id1)}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    assert Enum.count(searches) == 1

    # without available id filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{"id" => "0"}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    assert Enum.empty?(searches)

    # with available id list filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{"ids" => [to_string(id1), to_string(id2)]}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [_conv | _] = searches
    assert Enum.count(searches) == 2

    # with available phone_id filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 10},
          "filter" => %{"wa_phone_ids" => [to_string(wa_id1)]}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [_conv | _] = searches
    # assert Enum.count(conv) == 2

    # with id and wa_phone_id filter
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 10},
          "filter" => %{"id" => to_string(id1), "wa_phone_ids" => [to_string(wa_id1)]}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [_conv | _] = searches
    assert Enum.count(searches) == 1
    # assert Enum.count(conv) == 2

    # with search group and group label filter
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
