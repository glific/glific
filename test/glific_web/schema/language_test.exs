defmodule GlificWeb.Schema.Query.LanguageTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    Glific.Seeds.seed_language()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/languages/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/languages/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/languages/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/languages/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/languages/delete.gql")

  test "languages field returns list of languages" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    assert query_data == %{
             :data => %{
               "languages" => [
                 %{"label" => "English (United States)"},
                 %{"label" => "Hindi (India)"}
               ]
             }
           }
  end

  test "language id returns one language or nil" do
    label = "English (United States)"
    {:ok, lang} = Glific.Repo.fetch_by(Glific.Settings.Language, %{label: label})

    result = query_gql_by(:by_id, variables: %{"id" => lang.id})
    assert {:ok, query_data} = result

    language = get_in(query_data, [:data, "language", "language", "label"])
    assert language == label

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "language", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a language and test possible scenarios and errors" do
    result =
      query_gql_by(:create, variables: %{"input" => %{"label" => "Klingon", "locale" => "kl_KL"}})

    assert {:ok, query_data} = result

    language = get_in(query_data, [:data, "createLanguage", "language", "label"])
    assert language == "Klingon"

    _ =
      query_gql_by(:create, variables: %{"input" => %{"label" => "Klingon", "locale" => "kl_KL"}})

    result =
      query_gql_by(:create, variables: %{"input" => %{"label" => "Klingon", "locale" => "kl_KL"}})

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createLanguage", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update a language and test possible scenarios and errors" do
    label = "English (United States)"
    {:ok, lang} = Glific.Repo.fetch_by(Glific.Settings.Language, %{label: label})

    result =
      query_gql_by(:update,
        variables: %{"id" => lang.id, "input" => %{"label" => "Klingon", "locale" => "kl_KL"}}
      )

    assert {:ok, query_data} = result

    language = get_in(query_data, [:data, "updateLanguage", "language", "label"])
    assert language == "Klingon"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => lang.id,
          "input" => %{"label" => "Hindi (India)", "locale" => "hi_IN"}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateLanguage", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a language" do
    label = "English (United States)"
    {:ok, lang} = Glific.Repo.fetch_by(Glific.Settings.Language, %{label: label})

    result = query_gql_by(:delete, variables: %{"id" => lang.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteLanguage", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteLanguage", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
