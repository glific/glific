defmodule GlificWeb.Schema.SessionTemplateTest do
  use GlificWeb.ConnCase
  use Oban.Testing, repo: Glific.Repo
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Messages,
    Repo,
    Seeds.SeedsDev,
    Templates,
    Templates.SessionTemplate,
    Templates.TemplateWorker
  }

  setup do
    organization = SeedsDev.seed_organizations()
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    SeedsDev.hsm_templates(organization)
    Fixtures.session_template_fixture()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/session_templates/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/session_templates/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/session_templates/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/session_templates/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/session_templates/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/session_templates/delete.gql")
  load_gql(:sync, GlificWeb.Schema, "assets/gql/session_templates/sync.gql")

  load_gql(
    :create_from_message,
    GlificWeb.Schema,
    "assets/gql/session_templates/create_from_message.gql"
  )

  test "session templates field returns list of session_templates", %{manager: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    res =
      session_templates
      |> get_in([Access.all(), "body"])
      |> Enum.find(fn body -> body == "Default Template" end)

    assert res == "Default Template"
  end

  test "sync hsm with bsp", %{manager: user} do
    Templates.list_session_templates(%{
      filter: %{organization_id: user.organization_id, is_hsm: true}
    })

    [hsm, hsm2 | _] =
      Templates.list_session_templates(%{
        filter: %{organization_id: user.organization_id, is_hsm: true}
      })

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "success",
              "templates" => [
                %{
                  "id" => hsm.uuid,
                  "modifiedOn" =>
                    DateTime.to_unix(Timex.shift(hsm.updated_at, hours: -1), :millisecond),
                  "status" => "APPROVED",
                  "category" => "MARKETING",
                  "quality" => "UNKNOWN"
                },
                %{
                  "id" => hsm2.uuid,
                  "modifiedOn" =>
                    DateTime.to_unix(Timex.shift(hsm.updated_at, hours: -1), :millisecond),
                  "status" => "PENDING",
                  "category" => "AUTHENTICATION",
                  "quality" => "HIGH"
                }
              ]
            })
        }
    end)

    {:ok, %{data: %{"syncHSMTemplate" => %{"message" => message}}}} =
      auth_query_gql_by(:sync, user)

    assert_enqueued(
      worker: TemplateWorker,
      prefix: "global"
    )

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :default)

    {:ok, updated_hsm} =
      Repo.fetch_by(SessionTemplate, %{uuid: hsm.uuid, organization_id: user.organization_id})

    {:ok, updated_hsm2} =
      Repo.fetch_by(SessionTemplate, %{uuid: hsm2.uuid, organization_id: user.organization_id})

    assert message == "HSM sync job queued successfully"
    assert updated_hsm.category == "MARKETING"
    assert updated_hsm2.category == "AUTHENTICATION"
    assert updated_hsm.quality == "UNKNOWN"
    assert updated_hsm2.quality == "HIGH"
  end

  test "sync hsm with bsp if it doesn't establish a connection with gupshup test", %{
    manager: user
  } do
    user = Map.put(user, :organization_id, nil)
    Fixtures.session_template_fixture(%{label: "AAA"})

    result = auth_query_gql_by(:sync, user)
    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:errors])
    template_error = List.first(session_templates)
    assert template_error.message == "organization_id is not given"
  end

  test "count returns the number of session templates", %{manager: user} do
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

  test "session_templates field returns list of session_templates in desc order", %{manager: user} do
    Fixtures.session_template_fixture(%{label: "AAA"})

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

    [session_template | _] = session_templates
    assert get_in(session_template, ["label"]) == "AAA"
  end

  test "session_templates returns list of session templates in various filters", %{manager: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"body" => "Default Template"}})

    assert {:ok, query_data} = result

    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) == 1

    [session_template | _] = session_templates
    assert get_in(session_template, ["body"]) == "Default Template"

    # verifies the functionality of the category filter by querying session templates with the "UTILITY" category
    # and ensures the presence of atleast one filter
    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"category" => "UTILITY"}})

    assert {:ok, query_data} = result
    session_templates = get_in(query_data, [:data, "sessionTemplates"])
    assert length(session_templates) > 0

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

  test "session_template by id returns one session_template or nil", %{manager: user} do
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

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Label",
            "body" => "Test Template",
            "type" => "TEXT",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createSessionTemplate", "sessionTemplate", "label"])
    assert label == "Test Label"

    # try creating the same session template of a language twice
    _ =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Label 2",
            "body" => "Test Template 2",
            "type" => "TEXT",
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
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "createSessionTemplate", "errors", Access.at(0), "message"])

    assert message =~ "has already been taken"
  end

  test "update a session template and test possible scenarios and errors when is_hsm is false", %{
    manager: user
  } do
    label = "Default Template Label"

    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{
        label: label,
        organization_id: user.organization_id,
        is_hsm: false
      })

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => session_template.id,
          "input" => %{
            "label" => "New Test Label",
            "category" => "UTILITY",
            "body" => "new updated body"
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "updateSessionTemplate", "sessionTemplate", "label"])
    assert label == "New Test Label"
  end

  test "update a session template and test possible scenarios and errors when is_hsm is true", %{
    manager: user
  } do
    [hsm | _] =
      Templates.list_session_templates(%{
        filter: %{organization_id: user.organization_id, is_hsm: true}
      })

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => hsm.id,
          "input" => %{
            "label" => "New Test Label",
            "category" => "UTILITY",
            "body" => "new updated body"
          }
        }
      )

    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "updateSessionTemplate", "errors", Access.at(0), "message"])

    assert message == "Hsm: HSM is not approved yet, it can't be modified"
  end

  test "delete an session_template", %{manager: user} do
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

  test "create a session_template from message", %{manager: user} do
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

    assert message =~ "has already been taken"
  end

  test "create a session template with whatsapp form button", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "WA Form Template",
            "body" => "Template with WA Form Button",
            "type" => "TEXT",
            "languageId" => 1,
            "buttons" =>
              "[{\"type\":\"FLOW\",\"navigate_screen\":\"RECOMMEND\",\"text\":\"open\",\"flow_id\":\"850015687410293\",\"flow_action\":\"NAVIGATE\"}]",
            "buttonType" => "WHATSAPP_FORM"
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createSessionTemplate", "sessionTemplate", "label"])
    assert label == "WA Form Template"
  end
end
