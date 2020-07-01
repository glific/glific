defmodule GlificWeb.Schema.ProviderTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    Glific.SeedsDev.seed_providers()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/providers/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/providers/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/providers/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/providers/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/providers/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/providers/delete.gql")

  test "providers field returns list of providers" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    providers = get_in(query_data, [:data, "providers"])
    assert length(providers) > 0

    res =
      providers
      |> get_in([Access.all(), "name"])
      |> Enum.find(fn x -> x == "Default Provider" end)

    assert res == "Default Provider"
  end

  test "count returns the number of providers" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countProviders"]) == 3

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"name" => "This provider should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countProviders"]) == 0

    {:ok, query_data} =
      query_gql_by(:count, variables: %{"filter" => %{"name" => "Default Provider"}})

    assert get_in(query_data, [:data, "countProviders"]) == 1
  end

  test "provider id returns one provider or nil" do
    name = "Default Provider"
    {:ok, provider} = Glific.Repo.fetch_by(Glific.Partners.Provider, %{name: name})

    result = query_gql_by(:by_id, variables: %{"id" => provider.id})
    assert {:ok, query_data} = result

    provider = get_in(query_data, [:data, "provider", "provider", "name"])
    assert provider == name

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "provider", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a provider and test possible scenarios and errors" do
    name = "Provider Test Name"
    url = "Test url"
    api_end_point = "Test end point"

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "url" => url, "api_end_point" => api_end_point}}
      )

    assert {:ok, query_data} = result

    provider = get_in(query_data, [:data, "createProvider", "provider"])
    assert Map.get(provider, "name") == name
    assert Map.get(provider, "url") == url

    # try creating the same provider twice
    _ =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "url" => url, "api_end_point" => api_end_point}}
      )

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "url" => url, "api_end_point" => api_end_point}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createProvider", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update a provider and test possible scenarios and errors" do
    {:ok, provider} = Glific.Repo.fetch_by(Glific.Partners.Provider, %{name: "Default Provider"})

    name = "Provider Test Name"
    url = "Test url"
    api_end_point = "Test end point"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => provider.id,
          "input" => %{"name" => name, "url" => url, "api_end_point" => api_end_point}
        }
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateProvider", "provider", "name"])
    assert new_name == name

    # create a temp provider with a new name
    query_gql_by(:create,
      variables: %{
        "input" => %{"name" => "another provider", "url" => url, "api_end_point" => api_end_point}
      }
    )

    # ensure we cannot update an existing provider with the same name
    result =
      query_gql_by(:update,
        variables: %{
          "id" => provider.id,
          "input" => %{
            "name" => "another provider",
            "url" => url,
            "api_end_point" => api_end_point
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "updateProvider", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a provider" do
    {:ok, provider} = Glific.Repo.fetch_by(Glific.Partners.Provider, %{name: "Default Provider"})

    result = query_gql_by(:delete, variables: %{"id" => provider.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteProvider", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteProvider", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
