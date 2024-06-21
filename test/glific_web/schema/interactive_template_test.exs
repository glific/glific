defmodule GlificWeb.Schema.InteractiveTemplateTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Repo,
    Seeds.SeedsDev,
    Templates.InteractiveTemplate
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_interactives(organization)
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/interactives/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/interactives/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/interactives/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/interactives/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/interactives/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/interactives/delete.gql")
  load_gql(:copy, GlificWeb.Schema, "assets/gql/interactives/copy.gql")

  test "Interactive templates field returns list of interactives", %{manager: user} do
    {:ok, query_data} =
      auth_query_gql_by(:list, user,
        variables: %{"filter" => %{"term" => "Glific comes with all new features"}}
      )

    interactives = get_in(query_data, [:data, "interactiveTemplates"])
    assert length(interactives) > 0

    res =
      interactives
      |> get_in([Access.all(), "label"])
      |> Enum.find(fn label -> label == "Are you excited for *Glific*?" end)

    assert res == "Are you excited for *Glific*?"
  end

  test "Interactive templates field returns list of interactives filter by term", %{manager: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result
    interactives = get_in(query_data, [:data, "interactiveTemplates"])
    assert length(interactives) > 0

    res =
      interactives
      |> get_in([Access.all(), "label"])
      |> Enum.find(fn label -> label == "Interactive list" end)

    assert res == "Interactive list"
  end

  test "count returns the number of interactives", %{manager: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countInteractiveTemplates"]) > 4

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"label" => "Quick Reply Text Update"}}
      )

    assert get_in(query_data, [:data, "countInteractiveTemplates"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"label" => "Quick Reply Text"}})

    assert get_in(query_data, [:data, "countInteractiveTemplates"]) == 1
  end

  test "interactives field returns list of interactives in asc order", %{manager: user} do
    Fixtures.interactive_fixture(%{organization_id: user.organization_id})

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    interactives = get_in(query_data, [:data, "interactiveTemplates"])
    assert length(interactives) > 0

    [interactive | _] = interactives
    assert get_in(interactive, ["label"]) == "Are you excited for *Glific*?"
  end

  test "interactives field returns list of interactives in desc order", %{manager: user} do
    Fixtures.interactive_fixture(%{organization_id: user.organization_id})

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result

    interactives = get_in(query_data, [:data, "interactiveTemplates"])
    assert length(interactives) > 0

    [interactive | _] = interactives
    assert get_in(interactive, ["label"]) == "Send Location"
  end

  test "interactive template by id returns one interactive or nil", %{manager: user} do
    label = "Quick Reply Video"

    {:ok, interactive} =
      Repo.fetch_by(InteractiveTemplate, %{label: label, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => interactive.id})
    assert {:ok, query_data} = result

    interactive =
      get_in(query_data, [:data, "interactiveTemplate", "interactiveTemplate", "label"])

    assert interactive == label

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "interactiveTemplate", "errors", Access.at(0), "message"])

    assert message == "Resource not found"
  end

  test "create a interactive and test possible scenarios and errors", %{manager: user} do
    label = "Quick Reply Video"

    {:ok, interactive} =
      Repo.fetch_by(InteractiveTemplate, %{label: label, organization_id: user.organization_id})

    language_id = interactive.language_id

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Quick Reply Text Reply",
            "type" => "QUICK_REPLY",
            "interactive_content" => "{}",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    label =
      get_in(query_data, [:data, "createInteractiveTemplate", "interactiveTemplate", "label"])

    assert label == "Quick Reply Text Reply"

    # try creating the same session template of a language twice
    _ =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Quick Reply interactive",
            "type" => "QUICK_REPLY",
            "interactive_content" => "{}",
            "languageId" => language_id
          }
        }
      )

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Quick Reply interactive",
            "type" => "QUICK_REPLY",
            "interactive_content" => "{}",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "createInteractiveTemplate", "errors", Access.at(0), "message"])

    assert message =~ "has already been taken"
  end

  test "create a interactive with type as location_request_message", %{manager: user} do
    label = "Quick Reply Video"

    {:ok, interactive} =
      Repo.fetch_by(InteractiveTemplate, %{label: label, organization_id: user.organization_id})

    language_id = interactive.language_id

    interactive_content = %{
      "type" => "location_request_message",
      "body" => %{
        "type" => "text",
        "text" => "please share your location"
      },
      "action" => %{
        "name" => "send_location"
      }
    }

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Request Location",
            "type" => "LOCATION_REQUEST_MESSAGE",
            "interactive_content" => Jason.encode!(interactive_content),
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    label =
      get_in(query_data, [:data, "createInteractiveTemplate", "interactiveTemplate", "label"])

    assert label == "Request Location"
  end

  test "update interactive and test possible scenarios and errors", %{manager: user} do
    label = "Quick Reply Text"

    {:ok, interactive} =
      Repo.fetch_by(InteractiveTemplate, %{label: label, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{"id" => interactive.id, "input" => %{"label" => "Updated Quick Reply Text"}}
      )

    assert {:ok, query_data} = result

    label =
      get_in(query_data, [:data, "updateInteractiveTemplate", "interactiveTemplate", "label"])

    assert label == "Updated Quick Reply Text"

    # Try to update a template with same label
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => interactive.id,
          "input" => %{"label" => "Quick Reply Image"}
        }
      )

    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "updateInteractiveTemplate", "errors", Access.at(0), "message"])

    assert message =~ "has already been taken"
  end

  test "delete an interactive", %{manager: user} do
    {:ok, interactive} =
      Repo.fetch_by(InteractiveTemplate, %{
        label: "Quick Reply Text",
        organization_id: user.organization_id
      })

    result = auth_query_gql_by(:delete, user, variables: %{"id" => interactive.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteInteractiveTemplate", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "deleteInteractiveTemplate", "errors", Access.at(0), "message"])

    assert message == "Resource not found"
  end

  test "copy a interactive template and test possible scenarios and errors", %{manager: user} do
    {:ok, interactive_template} =
      Repo.fetch_by(InteractiveTemplate, %{
        label: "Quick Reply Text",
        organization_id: user.organization_id
      })

    result =
      auth_query_gql_by(:copy, user,
        variables: %{
          "id" => interactive_template.id,
          "input" => %{
            "label" => "Copy of Quick Reply Text",
            "languageId" => interactive_template.language_id
          }
        }
      )

    assert {:ok, query_data} = result

    assert "Copy of Quick Reply Text" ==
             get_in(query_data, [:data, "copyInteractiveTemplate", "interactiveTemplate", "label"])
  end
end
