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

  test "providers field returns list of providers", %{user: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    providers = get_in(query_data, [:data, "providers"])
    assert length(providers) > 0

    res =
      providers
      |> get_in([Access.all(), "name"])
      |> Enum.find(fn x -> x == "Glifproxy" end)

    assert res == "Glifproxy"
  end

  # @tag :pending
  test "count returns the number of providers", %{user: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countProviders"]) > 1

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"name" => "This provider should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countProviders"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "Default Provider"}})

    assert get_in(query_data, [:data, "countProviders"]) == 1
  end

  test "provider id returns one provider or nil", %{user: user} do
    name = "Default Provider"
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
    assert message == "has already been taken"
  end

  test "update a provider and test possible scenarios and errors", %{glific_admin: user} do
    {:ok, provider} = Repo.fetch_by(Provider, %{name: "Default Provider"})

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
    assert message == "has already been taken"
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
end
