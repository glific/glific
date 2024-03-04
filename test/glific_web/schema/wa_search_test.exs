defmodule GlificWeb.Schema.WaSearchTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts.Contact,
    Groups.WAGroup,
    Repo,
    Seeds.SeedsDev,
    WAGroup.WAManagedPhone
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

  test "wa_search with group filter ids", %{staff: user} do
    organization_id = 1

    {:ok, contact_1} =
      Repo.fetch_by(
        Contact,
        %{name: "NGO Main Account", organization_id: organization_id}
      )

    {:ok, contact_2} =
      Repo.fetch_by(
        Contact,
        %{name: "Default receiver", organization_id: organization_id}
      )

    {:ok, wa_managed_phone_1} =
      Repo.fetch_by(
        WAManagedPhone,
        %{contact_id: contact_1.id, organization_id: organization_id}
      )

    {:ok, wa_managed_phone_2} =
      Repo.fetch_by(
        WAManagedPhone,
        %{contact_id: contact_2.id, organization_id: organization_id}
      )

    {:ok, wa_group_1} =
      Repo.fetch_by(
        WAGroup,
        %{wa_managed_phone_id: wa_managed_phone_1.id, organization_id: organization_id}
      )

    {:ok, wa_group_2} =
      Repo.fetch_by(
        WAGroup,
        %{wa_managed_phone_id: wa_managed_phone_2.id, organization_id: organization_id}
      )

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

    assert {:ok, %{data: %{"search" => searches}} = _query_data} = result
    [conv | _] = searches
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
  end
end
