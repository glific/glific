defmodule GlificWeb.Schema.Query.SessionTemplateTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_session_templates(lang)
    :ok
  end

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
      |> Enum.find(fn x -> x == "Default Session Template" end)

    assert res == "Default Session Template"
  end

  test "session_template by id returns one session_template or nil" do
    body = "Default Session Template"

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

  test "delete an session_template" do
    {:ok, session_template} =
      Glific.Repo.fetch_by(Glific.Templates.SessionTemplate, %{body: "Default Session Template"})

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
