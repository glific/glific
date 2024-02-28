defmodule GlificWeb.Schema.WaSearchTest do
  alias Glific.WAGroup.WAManagedPhone
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
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
  test "wa_search with group filter ids", %{staff: user} do
    [id1, id2] =
      WAGroup
      |> where([grp], grp.organization_id == 1)
      |> select([grp], grp.id)
      |> Repo.all()

    [wa_id1, _wa_id2] =
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
          "filter" => %{"id" => "5"}
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
    [conv | _] = searches
    assert Enum.count(conv) == 2

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
    [conv | _] = searches
    assert Enum.count(searches) == 1
    assert Enum.count(conv) == 2
  end
end
