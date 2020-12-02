defmodule GlificWeb.Schema.SessionTemplateTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Messages,
    Repo,
    Seeds.SeedsDev,
    Templates.SessionTemplate
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    Fixtures.session_template_fixture()
    :ok
  end

  load_gql(
    :send_session_message,
    GlificWeb.Schema,
    "assets/gql/session_templates/send_session_message.gql"
  )

  load_gql(:count, GlificWeb.Schema, "assets/gql/session_templates/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/session_templates/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/session_templates/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/session_templates/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/session_templates/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/session_templates/delete.gql")

  load_gql(
    :create_from_message,
    GlificWeb.Schema,
    "assets/gql/session_templates/create_from_message.gql"
  )

  test "session templates field returns list of session_templates", %{staff: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    res =
      session_templates
      |> get_in([Access.all(), "body"])
      |> Enum.find(fn x -> x == "Default Template" end)

    assert res == "Default Template"
  end

  test "count returns the number of session templates", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countSessionTemplates"]) > 4

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"label" => "This session template should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countSessionTemplates"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"label" => "Default Template Label"}}
      )

    assert get_in(query_data, [:data, "countSessionTemplates"]) == 1
  end

  test "session_templates field returns list of session_templates in desc order", %{staff: user} do
    Fixtures.session_template_fixture(%{label: "AAA"})

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    [session_template | _] = session_templates
    assert get_in(session_template, ["label"]) == "AAA"
  end

  test "session_templates returns list of session templates in various filters", %{staff: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"body" => "Default Template"}})

    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) == 1

    [session_template | _] = session_templates
    assert get_in(session_template, ["body"]) == "Default Template"

    # get language_id for next test
    parent_id = String.to_integer(get_in(session_template, ["id"]))
    language_id = String.to_integer(get_in(session_template, ["language", "id"]))

    result =
      auth_query_gql_by(:list, user,
        variables: %{"filter" => %{"parent" => "Default Template Label"}}
      )

    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"parentId" => parent_id}})
    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"languageId" => language_id}})

    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"language" => "English"}})
    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"isHsm" => true}})
    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) >= 1

    Fixtures.session_template_fixture(%{label: "term_filter"})
    Fixtures.session_template_fixture(%{label: "label2", body: "term_filter"})
    Fixtures.session_template_fixture(%{label: "label3", shortcode: "term_filter"})

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"term" => "term_filter"}})
    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) == 3
  end

  test "session_template by id returns one session_template or nil", %{staff: user} do
    body = "Default Template"

    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{body: body, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => session_template.id})
    assert {:ok, query_data} = result

    session_template = get_in(query_data, [:data, "sessionTemplate", "sessionTemplate", "body"])
    assert session_template == body

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "sessionTemplate", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a session_template and test possible scenarios and errors", %{staff: user} do
    label = "Default Template Label"

    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{label: label, organization_id: user.organization_id})

    language_id = session_template.language_id
    translations = %{
      2 => %{
        number_parameters: 0,
        language_id: 2,
        body: "एक और टेम्पलेट"
      }
    }
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Label",
            "body" => "Test Template",
            "type" => "TEXT",
            "languageId" => language_id,
            "translations" => Jason.encode!(translations)
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createSessionTemplate", "sessionTemplate", "label"])
    translations = get_in(query_data, [:data, "createSessionTemplate", "sessionTemplate", "translations"])
    assert label == "Test Label"
    assert translations == "{\"2\":{\"number_parameters\":0,\"language_id\":2,\"body\":\"एक और टेम्पलेट\"}}"

    # try creating the same session template of a language twice
    _ =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Label 2",
            "body" => "Test Template 2",
            "type" => "TEXT",
            "translations" => translations,
            "languageId" => language_id
          }
        }
      )

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Label 2",
            "body" => "Test Template 2",
            "type" => "TEXT",
            "translations" => translations,
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "createSessionTemplate", "errors", Access.at(0), "message"])

    assert message == "has already been taken"
  end

  test "update a session template and test possible scenarios and errors", %{staff: user} do
    label = "Default Template Label"

    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{label: label, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{"id" => session_template.id, "input" => %{"label" => "New Test Label"}}
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateSessionTemplate", "sessionTemplate", "label"])
    assert label == "New Test Label"

    # Try to update a template with same label and language id
    result =
      auth_query_gql_by(:update, user,
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

  test "delete an session_template", %{staff: user} do
    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{
        body: "Default Template",
        organization_id: user.organization_id
      })

    result = auth_query_gql_by(:delete, user, variables: %{"id" => session_template.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteSessionTemplate", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "deleteSessionTemplate", "errors", Access.at(0), "message"])

    assert message == "Resource not found"
  end

  test "send session message", %{staff: user} do
    body = "Default Template"

    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{body: body, organization_id: user.organization_id})

    name = "Adelle Cavin"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:send_session_message, user,
        variables: %{"id" => session_template.id, "receiver_id" => contact.id}
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "sendSessionMessage", "errors"]) == [nil]
  end

  test "create a session_template from message", %{staff: user} do
    label = "Default Template Label"

    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{label: label, organization_id: user.organization_id})

    language_id = session_template.language_id
    [message | _] = Messages.list_messages(%{filter: %{organization_id: user.organization_id}})

    result =
      auth_query_gql_by(:create_from_message, user,
        variables: %{
          "messageId" => message.id,
          "input" => %{
            "label" => "From Message",
            "shortcode" => "from",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "createTemplateFormMessage", "sessionTemplate", "label"])
    assert label == "From Message"

    result =
      auth_query_gql_by(:create_from_message, user,
        variables: %{
          "messageId" => message.id,
          "input" => %{
            "label" => "From Message",
            "shortcode" => "from",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "createTemplateFormMessage", "errors", Access.at(0), "message"])

    assert message == "has already been taken"
  end
end
