defmodule GlificWeb.Schema.LanguageTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  load_gql(:count, GlificWeb.Schema, "assets/gql/languages/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/languages/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/languages/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/languages/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/languages/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/languages/delete.gql")

  test "languages field returns list of languages" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    label_0 = get_in(query_data, [:data, "languages", Access.at(0), "label"])
    label_1 = get_in(query_data, [:data, "languages", Access.at(1), "label"])

    assert (label_0 == "English (United States)" and label_1 == "Hindi") or
             (label_1 == "English (United States)" and label_0 == "Hindi")
  end

  test "count returns the number of languages" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countLanguages"]) == 2
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
      query_gql_by(:create,
        variables: %{
          "input" => %{"label" => "Klingon", "labelLocale" => "Klingon", "locale" => "kl_KL"}
        }
      )

    assert {:ok, query_data} = result
    language = get_in(query_data, [:data, "createLanguage", "language", "label"])
    assert language == "Klingon"

    _ =
      query_gql_by(:create,
        variables: %{
          "input" => %{"label" => "Klingon", "labelLocale" => "Klingon", "locale" => "kl_KL"}
        }
      )

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{"label" => "Klingon", "labelLocale" => "Klingon", "locale" => "kl_KL"}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createLanguage", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update a language and test possible scenarios and errors" do
    label = "English (United States)"
    {:ok, lang} = Glific.Repo.fetch_by(Glific.Settings.Language, %{label: label})

    result =
      query_gql_by(:update,
        variables: %{
          "id" => lang.id,
          "input" => %{"label" => "Klingon", "labelLocale" => "Klinfon", "locale" => "kl_KL"}
        }
      )

    assert {:ok, query_data} = result

    language = get_in(query_data, [:data, "updateLanguage", "language", "label"])
    assert language == "Klingon"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => lang.id,
          "input" => %{"label" => "Hindi", "labelLocale" => "Hindi", "locale" => "hi_IN"}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateLanguage", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a language" do
    # first create a language
    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{"label" => "Klingon", "labelLocale" => "Klingon", "locale" => "kl_KL"}
        }
      )
    assert {:ok, query_data} = result
    language = get_in(query_data, [:data, "createLanguage", "language", "label"])
    language_id =  get_in(query_data, [:data, "createLanguage", "language", "id"])
    assert language == "Klingon"

    # now lets delete it
    result = query_gql_by(:delete, variables: %{"id" => language_id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteLanguage", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteLanguage", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
