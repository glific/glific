defmodule GlificWeb.Schema.WaSearchTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  alias Glific.Seeds.SeedsDev

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
          "waMessageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, %{data: %{"waSearch" => searches}} = _query_data} = result
    [conv | _] = searches
    assert Enum.count(searches) == 1
    assert Enum.count(conv["wa_messages"]) == 1

    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{"limit" => 2},
          "waMessageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, %{data: %{"waSearch" => searches}} = _query_data} = result
    [_conv | _] = searches
    assert Enum.count(searches) == 2

    # without group limit
    result =
      auth_query_gql_by(:wa_search, user,
        variables: %{
          "waGroupOpts" => %{},
          "waMessageOpts" => %{"limit" => 1}
        }
      )

    assert {:ok, %{data: %{"waSearch" => searches}} = _query_data} = result
    [_conv | _] = searches
    assert Enum.count(searches) == 2
  end
end
