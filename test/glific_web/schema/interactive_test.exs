defmodule GlificWeb.Schema.InteractiveTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Messages.Interactive,
    Repo,
    Seeds.SeedsDev
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

  test "session templates field returns list of interactives", %{staff: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result
    interactives = get_in(query_data, [:data, "interactives"])
    assert length(interactives) > 0

    res =
      interactives
      |> get_in([Access.all(), "label"])
      |> Enum.find(fn x -> x == "Interactive list" end)

    assert res == "Interactive list"
  end

  test "count returns the number of interactives", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countInteractives"]) > 4

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"label" => "Quick Reply Text Update"}}
      )

    assert get_in(query_data, [:data, "countInteractives"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"label" => "Quick Reply Text"}})

    assert get_in(query_data, [:data, "countInteractives"]) == 1
  end

  test "interactives field returns list of interactives in asc order", %{staff: user} do
    Fixtures.interactive_fixture(%{organization_id: user.organization_id})

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    interactives = get_in(query_data, [:data, "interactives"])
    assert length(interactives) > 0

    [interactive | _] = interactives
    assert get_in(interactive, ["label"]) == "Interactive list"
  end

  test "interactives field returns list of interactives in desc order", %{staff: user} do
    Fixtures.interactive_fixture(%{organization_id: user.organization_id})

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result

    interactives = get_in(query_data, [:data, "interactives"])
    assert length(interactives) > 0

    [interactive | _] = interactives
    assert get_in(interactive, ["label"]) == "Quick Reply Video"
  end

  test "interactive by id returns one interactive or nil", %{staff: user} do
    label = "Quick Reply Video"

    {:ok, interactive} =
      Repo.fetch_by(Interactive, %{label: label, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => interactive.id})
    assert {:ok, query_data} = result

    interactive = get_in(query_data, [:data, "interactive", "interactive", "label"])
    assert interactive == label

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "interactive", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a interactive and test possible scenarios and errors", %{staff: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Quick Reply Text Reply",
            "type" => "QUICK_REPLY",
            "interactive_content" => "{}"
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createInteractive", "interactive", "label"])
    assert label == "Quick Reply Text Reply"

    # try creating the same session template of a language twice
    _ =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Quick Reply interactive",
            "type" => "QUICK_REPLY",
            "interactive_content" => "{}"
          }
        }
      )

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Quick Reply interactive",
            "type" => "QUICK_REPLY",
            "interactive_content" => "{}"
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createInteractive", "errors", Access.at(0), "message"])

    assert message == "has already been taken"
  end

  test "update interactive and test possible scenarios and errors", %{staff: user} do
    label = "Quick Reply Text"

    {:ok, interactive} =
      Repo.fetch_by(Interactive, %{label: label, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{"id" => interactive.id, "input" => %{"label" => "Updated Quick Reply Text"}}
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateInteractive", "interactive", "label"])
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

    message = get_in(query_data, [:data, "updateInteractive", "errors", Access.at(0), "message"])

    assert message == "has already been taken"
  end

  test "delete an interactive", %{staff: user} do
    {:ok, interactive} =
      Repo.fetch_by(Interactive, %{
        label: "Quick Reply Text",
        organization_id: user.organization_id
      })

    result = auth_query_gql_by(:delete, user, variables: %{"id" => interactive.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteInteractive", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteInteractive", "errors", Access.at(0), "message"])

    assert message == "Resource not found"
  end
end
