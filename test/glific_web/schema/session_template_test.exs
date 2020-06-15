defmodule GlificWeb.Schema.Query.SessionTemplateTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_session_templates(lang)
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/session_templates/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/session_templates/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/session_templates/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/session_templates/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/session_templates/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/session_templates/delete.gql")

  test "session_templates field returns list of session_templates" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    res =
      session_templates
      |> get_in([Access.all(), "body"])
      |> Enum.find(fn x -> x == "Default Template" end)

    assert res == "Default Template"
  end

  test "count returns the number of session templates" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countSessionTemplates"]) == 4

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"label" => "This session template should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countSessionTemplates"]) == 0

    {:ok, query_data} =
      query_gql_by(:count, variables: %{"filter" => %{"label" => "Default Template Label"}})

    assert get_in(query_data, [:data, "countSessionTemplates"]) == 1
  end

  test "session_templates field returns list of session_templates in desc order" do
    result = query_gql_by(:list, variables: %{"order" => "ASC"})
    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    [session_template | _] = session_templates
    assert get_in(session_template, ["body"]) == "Another Template"
  end

  test "session_templates field returns list of session templates in various filters" do
    result = query_gql_by(:list, variables: %{"filter" => %{"body" => "Default Template"}})
    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    [session_template | _] = session_templates
    assert get_in(session_template, ["body"]) == "Default Template"

    # get language_id for next test
    parent_id = String.to_integer(get_in(session_template, ["id"]))
    language_id = String.to_integer(get_in(session_template, ["language", "id"]))

    result =
      query_gql_by(:list, variables: %{"filter" => %{"parent" => "Default Template Label"}})

    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    result = query_gql_by(:list, variables: %{"filter" => %{"parentId" => parent_id}})
    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    result = query_gql_by(:list, variables: %{"filter" => %{"languageId" => language_id}})
    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    result = query_gql_by(:list, variables: %{"filter" => %{"language" => "English"}})
    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0
  end

  test "session_template by id returns one session_template or nil" do
    body = "Default Template"

    {:ok, session_template} =
      Glific.Repo.fetch_by(Glific.Templates.SessionTemplate, %{body: body})

    result = query_gql_by(:by_id, variables: %{"id" => session_template.id})
    assert {:ok, query_data} = result

    session_template = get_in(query_data, [:data, "sessionTemplate", "sessionTemplate", "body"])
    assert session_template == body

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "sessionTemplate", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a session_template and test possible scenarios and errors" do
    label = "Default Template Label"

    {:ok, session_template} =
      Glific.Repo.fetch_by(Glific.Templates.SessionTemplate, %{label: label})

    language_id = session_template.language_id

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "label" => "Test Label",
            "body" => "Test Template",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createSessionTemplate", "sessionTemplate", "label"])
    assert label == "Test Label"

    # try creating the same session template of a language twice
    _ =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "label" => "Test Label 2",
            "body" => "Test Template 2",
            "languageId" => language_id
          }
        }
      )

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "label" => "Test Label 2",
            "body" => "Test Template 2",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "createSessionTemplate", "errors", Access.at(0), "message"])

    assert message == "has already been taken"
  end

  test "update a session template and test possible scenarios and errors" do
    label = "Default Template Label"

    {:ok, session_template} =
      Glific.Repo.fetch_by(Glific.Templates.SessionTemplate, %{label: label})

    result =
      query_gql_by(:update,
        variables: %{"id" => session_template.id, "input" => %{"label" => "New Test Label"}}
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateSessionTemplate", "sessionTemplate", "label"])
    assert label == "New Test Label"

    # Try to update a template with same label and language id
    result =
      query_gql_by(:update,
        variables: %{
          "id" => session_template.id,
          "input" => %{"label" => "Another Template Label"}
        }
      )

    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "updateSessionTemplate", "errors", Access.at(0), "message"])

    assert message == "has already been taken"
  end

  test "delete an session_template" do
    {:ok, session_template} =
      Glific.Repo.fetch_by(Glific.Templates.SessionTemplate, %{body: "Default Template"})

    result = query_gql_by(:delete, variables: %{"id" => session_template.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteSessionTemplate", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "deleteSessionTemplate", "errors", Access.at(0), "message"])

    assert message == "Resource not found"
  end
end
