defmodule GlificWeb.Schema.WaSearchTest do
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
          "waGroupOpts" => %{"limit" => 1},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [conv | _] = searches
    assert Enum.count(searches) == 1
    assert Enum.count(conv["messages"]) == 1

    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{"limit" => 2},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [_conv | _] = searches
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
    [_conv | _] = searches
    assert Enum.count(searches) == 2
  end

  @tag :wa_search
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

    # without available id filters
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

    # with available id list filters
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1},
          "filter" => %{"ids" => [to_string(wa_group_1.id), to_string(wa_group_2.id)]}
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
          "filter" => %{"wa_phone_ids" => [to_string(wa_managed_phone_1.id)]}
        }
      )

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result |> IO.inspect()
    [conv | _] = searches
    # IO.inspect(conv)
    assert Enum.count(conv) == 2

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
    [conv | _] = searches
    assert Enum.count(searches) == 1
    assert Enum.count(conv) == 2

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
end
