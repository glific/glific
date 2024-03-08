defmodule GlificWeb.Schema.WAGroupCollectionTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Groups,
    Groups.WaGroupsCollections,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/wa_groups/list.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/wa_group_collection/create.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/wa_groups/count.gql")

  load_gql(
    :update_collection,
    GlificWeb.Schema,
    "assets/gql/wa_group_collection/update_collection.gql"
  )

  load_gql(
    :update_wa_group,
    GlificWeb.Schema,
    "assets/gql/wa_group_collection/update_wa_group.gql"
  )

  test "a list wa group collection", %{user: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    group = Fixtures.group_fixture(%{organization_id: user.organization_id})

    WaGroupsCollections.update_collection_wa_group(%{
      organization_id: user.organization_id,
      group_id: group.id,
      add_wa_group_ids: [wa_group.id],
      delete_wa_group_ids: []
    })

    limit = 4

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => limit, "offset" => 0}})

    assert {:ok, query_data} = result

    wa_groups_collection = get_in(query_data, [:data, "waGroups"])
    assert length(wa_groups_collection) > 0
    assert length(wa_groups_collection) <= limit

    # get the wa group using group id
    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{
            "includeGroups" => [to_string(group.id)]
          }
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "waGroups"])) == 1
  end

  test "create wa groups collection", %{user: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    group = Fixtures.group_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "group_id" => group.id
          }
        }
      )

    assert {:ok, query_data} = result

    wa_group_collection =
      get_in(query_data, [:data, "createWaGroupsCollection", "waGroupsCollection"])

    assert wa_group_collection["group"]["id"] |> String.to_integer() == group.id
    wa_group_id = Enum.at(wa_group_collection["group"]["waGroups"], 0) |> Map.get("id")
    assert wa_group_id |> String.to_integer() == wa_group.id
  end

  test "count the whatsapp groups in a collection", %{user: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    group = Fixtures.group_fixture(%{organization_id: user.organization_id})

    WaGroupsCollections.update_collection_wa_group(%{
      organization_id: user.organization_id,
      group_id: group.id,
      add_wa_group_ids: [wa_group.id],
      delete_wa_group_ids: []
    })

    result =
      auth_query_gql_by(:count, user,
        variables: %{
          "filter" => %{
            "includeGroups" => group.id
          }
        }
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "waGroupsCount"]) == 1
  end

  test "update collection using wa group ids", %{user: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    group = Fixtures.group_fixture(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update_collection, user,
        variables: %{
          "input" => %{
            "groupId" => group.id,
            "add_wa_group_ids" => [wa_group.id],
            "delete_wa_group_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result

    wa_group_collection =
      get_in(query_data, [:data, "updateCollectionWaGroup", "collectionWaGroups"])

    collection = Enum.at(wa_group_collection, 0)
    assert collection["group"]["id"] |> String.to_integer() == group.id
    assert collection["group"]["label"] == group.label

    # delete the collection
    result =
      auth_query_gql_by(:update_collection, user,
        variables: %{
          "input" => %{
            "groupId" => group.id,
            "add_wa_group_ids" => [],
            "delete_wa_group_ids" => [wa_group.id]
          }
        }
      )

    assert {:ok, query_data} = result
    wa_group_collection = get_in(query_data, [:data, "updateCollectionWaGroup"])
    assert wa_group_collection["waGroupsDeleted"] == 1

    # incorrect wa group id
    result =
      auth_query_gql_by(:update_collection, user,
        variables: %{
          "input" => %{
            "group_id" => group.id,
            "add_wa_group_ids" => ["-1"],
            "delete_wa_group_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result

    wa_group_collection =
      get_in(query_data, [:data, "updateCollectionWaGroup", "collectionWaGroups"])

    assert wa_group_collection == []
  end

  test "update wa groups using group ids", %{user: user} do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    [group1, group2 | _tail] = Groups.list_groups(%{organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update_wa_group, user,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "add_group_ids" => [group1.id, group2.id],
            "delete_group_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result

    wa_group_collection =
      get_in(query_data, [:data, "updateWaGroupCollection", "collectionWaGroups"])

    assert length(wa_group_collection) == 2

    # delete the collection
    result =
      auth_query_gql_by(:update_wa_group, user,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "add_group_ids" => [],
            "delete_group_ids" => [group1.id, group2.id]
          }
        }
      )

    assert {:ok, query_data} = result
    wa_group_collection = get_in(query_data, [:data, "updateWaGroupCollection"])
    assert wa_group_collection["waGroupsDeleted"] == 2

    # incorrect wa group id
    result =
      auth_query_gql_by(:update_wa_group, user,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "add_group_ids" => ["-1"],
            "delete_group_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result

    wa_group_collection =
      get_in(query_data, [:data, "updateWaGroupCollection", "collectionWaGroups"])

    assert wa_group_collection == []
  end
end
