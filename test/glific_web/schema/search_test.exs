defmodule GlificWeb.Schema.SearchTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    Glific.Seeds.seed_saved_searches()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/searches/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/searches/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/searches/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/searches/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/searches/delete.gql")


  test "search field returns list of searches" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result
    saved_searches = get_in(query_data, [:data, "savedSearches"])
    assert length(saved_searches) > 0
    [saved_search | _] = saved_searches
    assert get_in(saved_search, ["label"]) != nil
  end

  test "savedSearch id returns one saved search or nil" do
    [saved_search | _tail] = Glific.Searches.list_saved_searches()

    result = query_gql_by(:by_id, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result

    assert saved_search.label == get_in(query_data, [:data, "savedSearch", "savedSearch", "label"])

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "savedSearch", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end


  test "save a search and test possible scenarios and errors" do
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"label" => "Test search", "args" => Jason.encode!(%{term: "Default"})}}
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createSavedSearch", "savedSearch", "label"])
    assert label == "Test search"

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"label" => "Test search", "args" => Jason.encode!(%{term: "Default"})}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createSavedSearch", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end


  test "update a saved search and test possible scenarios and errors" do
    [saved_search, saved_search2 | _tail] = Glific.Searches.list_saved_searches()
    result =
      query_gql_by(:update,
        variables: %{"id" => saved_search.id, "input" => %{"label" => "New Test Search Label"}}
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateSavedSearch", "savedSearch", "label"])
    assert label == "New Test Search Label"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => saved_search.id,
          "input" => %{"label" => saved_search2.label}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateSavedSearch", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a saved search" do
    [saved_search | _tail] = Glific.Searches.list_saved_searches()

    result = query_gql_by(:delete, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteSavedSearch", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => saved_search.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteSavedSearch", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
