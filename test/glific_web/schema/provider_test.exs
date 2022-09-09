defmodule GlificWeb.Schema.ProviderTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  alias Glific.{
    Partners.Provider,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_providers()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/providers/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/providers/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/providers/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/providers/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/providers/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/providers/delete.gql")
  load_gql(:bspbalance, GlificWeb.Schema, "assets/gql/providers/bspbalance.gql")
  load_gql(:quality_rating, GlificWeb.Schema, "assets/gql/providers/quality_rating.gql")

  test "providers field returns list of providers", %{user: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    providers = get_in(query_data, [:data, "providers"])
    assert length(providers) > 0

    res =
      providers
      |> get_in([Access.all(), "name"])
      |> Enum.find(fn x -> x == "Gupshup" end)

    assert res == "Gupshup"
  end

  test "count returns the number of providers", %{user: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countProviders"]) > 1

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"name" => "This provider should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countProviders"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "Gupshup Enterprise"}})

    assert get_in(query_data, [:data, "countProviders"]) == 1
  end

  test "provider id returns one provider or nil", %{user: user} do
    name = "Gupshup Enterprise"
    {:ok, provider} = Repo.fetch_by(Provider, %{name: name})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => provider.id})
    assert {:ok, query_data} = result

    provider = get_in(query_data, [:data, "provider", "provider", "name"])
    assert provider == name

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "provider", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a provider and test possible scenarios and errors", %{glific_admin: user} do
    name = "Provider Test Name"
    shortcode = "providershortcode"
    group = "bsp"
    description = "BSP provider"
    keys = "{}"
    secrets = "{}"

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => name,
            "shortcode" => shortcode,
            "group" => group,
            "description" => description,
            "keys" => keys,
            "secrets" => secrets
          }
        }
      )

    assert {:ok, query_data} = result

    provider = get_in(query_data, [:data, "createProvider", "provider"])
    assert Map.get(provider, "name") == name
    assert Map.get(provider, "description") == description

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => name,
            "shortcode" => shortcode,
            "group" => group,
            "keys" => keys,
            "secrets" => secrets
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createProvider", "errors", Access.at(0), "message"])
    assert message =~ "has already been taken"
  end

  test "update a provider and test possible scenarios and errors", %{glific_admin: user} do
    {:ok, provider} = Repo.fetch_by(Provider, %{name: "Gupshup Enterprise"})

    name = "Provider Test Name"
    shortcode = "providershortcode"
    group = "bsp"
    keys = "{}"
    secrets = "{}"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => provider.id,
          "input" => %{
            "name" => name
          }
        }
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateProvider", "provider", "name"])
    assert new_name == name

    # create a temp provider with a new name
    auth_query_gql_by(:create, user,
      variables: %{
        "input" => %{
          "name" => "another provider",
          "shortcode" => shortcode,
          "group" => group,
          "keys" => keys,
          "secrets" => secrets
        }
      }
    )

    # ensure we cannot update an existing provider with the same name
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => provider.id,
          "input" => %{
            "name" => "another provider"
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "updateProvider", "errors", Access.at(0), "message"])
    assert message =~ "has already been taken"
  end

  test "delete a provider", %{glific_admin: user} do
    {:ok, provider} = Repo.fetch_by(Provider, %{name: "Default Provider"})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => provider.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteProvider", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteProvider", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "provider bsp balance", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: "{\"balance\":0.787,\"status\":\"success\"}"
        }
    end)

    result = auth_query_gql_by(:bspbalance, user)
    assert {:ok, query_data} = result

    balance =
      get_in(query_data, [:data, "bspbalance"])
      |> Jason.decode!()

    assert balance["balance"] == 0.787
  end

  test "get quality rating details", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "token" => "some random partner token"
            })
        }

      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "token" => %{"token" => "some random app token"},
              "currentLimit" => "Tier100K",
              "oldLimit" => "Tier1K",
              "event" => "upgrade"
            })
        }
    end)

    result = auth_query_gql_by(:quality_rating, user)
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "qualityRating", "current_limit"]) == "Tier100K"
    assert get_in(query_data, [:data, "qualityRating", "event"]) == "upgrade"
    assert get_in(query_data, [:data, "qualityRating", "previous_limit"]) == "Tier1K"
  end
end
