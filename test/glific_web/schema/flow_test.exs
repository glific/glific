defmodule GlificWeb.Schema.FlowTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Fixtures,
    Flows,
    Flows.Flow,
    Flows.FlowRevision,
    Groups,
    Repo,
    Seeds.SeedsDev,
    State
  }

  setup do
    SeedsDev.seed_test_flows()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/flows/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/flows/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/flows/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/flows/update.gql")
  load_gql(:export_flow, GlificWeb.Schema, "assets/gql/flows/export_flow.gql")
  load_gql(:import_flow, GlificWeb.Schema, "assets/gql/flows/import_flow.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/flows/delete.gql")
  load_gql(:publish, GlificWeb.Schema, "assets/gql/flows/publish.gql")
  load_gql(:contact_flow, GlificWeb.Schema, "assets/gql/flows/contact_flow.gql")
  load_gql(:contact_resume, GlificWeb.Schema, "assets/gql/flows/contact_resume.gql")
  load_gql(:group_flow, GlificWeb.Schema, "assets/gql/flows/group_flow.gql")
  load_gql(:copy, GlificWeb.Schema, "assets/gql/flows/copy.gql")
  load_gql(:flow_get, GlificWeb.Schema, "assets/gql/flows/flow_get.gql")
  load_gql(:flow_rel, GlificWeb.Schema, "assets/gql/flows/flow_release.gql")

  test "flows field returns list of flows", %{staff: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) > 0

    res = flows |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "Help Workflow" end)
    assert res == "Help Workflow"

    [flow | _] = flows
    assert get_in(flow, ["id"]) > 0
  end

  test "flows field returns list of filtered flows", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"keyword" => "help"}})
    assert {:ok, query_data} = result

    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) == 1

    name = "Test Workflow"
    {:ok, flow} = Repo.fetch_by(Flow, %{name: name, organization_id: user.organization_id})

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"uuid" => flow.uuid}})
    assert {:ok, query_data} = result

    flow_uuid = get_in(query_data, [:data, "flows", Access.at(0), "uuid"])
    assert flow_uuid == flow.uuid

    # testing flow filter with is_active
    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"is_active" => flow.is_active}})

    assert {:ok, query_data} = result
    flow_name = get_in(query_data, [:data, "flows", Access.at(0), "name"])
    assert flow_name == "Help Workflow"

    result =
      auth_query_gql_by(:list, user,
        variables: %{"filter" => %{"is_background" => flow.is_background}}
      )

    assert {:ok, query_data} = result
    flow_name = get_in(query_data, [:data, "flows", Access.at(0), "name"])
    assert flow_name == "Help Workflow"
  end

  test "flows field returns list of flows filtered by status", %{manager: user} do
    # Create a new flow
    auth_query_gql_by(:create, user,
      variables: %{"input" => %{"name" => "New Flow", "keywords" => "new"}}
    )

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"status" => "draft"}})
    assert {:ok, query_data} = result
    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) == 1
  end

  test "flow field id returns one flow or nil", %{staff: user} do
    name = "Test Workflow"
    {:ok, flow} = Repo.fetch_by(Flow, %{name: name, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result

    flow = get_in(query_data, [:data, "flow", "flow", "name"])
    assert flow == name

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "flow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "definiton field returns one flow definition or nil", %{staff: user} do
    [flow | _] = Flows.list_flows(%{filter: %{name: "activity"}})

    name = flow.name
    flow_id = flow.id

    {:ok, flow} =
      Repo.fetch_by(FlowRevision, %{flow_id: flow_id, organization_id: user.organization_id})

    result = auth_query_gql_by(:export_flow, user, variables: %{"id" => flow.flow_id})
    assert {:ok, query_data} = result

    data =
      get_in(query_data, [:data, "exportFlow", "export_data"])
      |> Jason.decode!()

    assert length(data["flows"]) > 0

    assert Enum.any?(data["flows"], fn flow -> flow["definition"]["name"] == name end)
  end

  test "export flow and the import flow", %{staff: user} do
    [flow | _] = Flows.list_flows(%{filter: %{name: "New Contact Workflow"}})

    flow_id = flow.id

    Repo.fetch_by(FlowRevision, %{flow_id: flow_id, organization_id: user.organization_id})

    result = auth_query_gql_by(:export_flow, user, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result

    data =
      get_in(query_data, [:data, "exportFlow", "export_data"])
      |> Jason.decode!()

    assert length(data["flows"]) > 0

    # Deleting all existing flows as importing New Contact Flow creates sub flows as well
    Flows.list_flows(%{})
    |> Enum.each(fn flow -> Flows.delete_flow(flow) end)

    # Deleting all existing collections as importing New Contact Flow creates collections
    Groups.list_groups(%{})
    |> Enum.each(fn flow -> Groups.delete_group(flow) end)

    import_flow = data |> Jason.encode!()
    result = auth_query_gql_by(:import_flow, user, variables: %{"flow" => import_flow})
    assert {:ok, query_data} = result
    assert true = get_in(query_data, [:data, "importFlow", "success"])
    [group | _] = Groups.list_groups(%{filter: %{label: "Optin contacts"}})
    assert group.label == "Optin contacts"
  end

  test "create a flow and test possible scenarios and errors", %{manager: user} do
    name = "Flow Test Name"
    keywords = ["test_keyword", "test_keyword_2"]

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"name" => name, "keywords" => keywords}
        }
      )

    assert {:ok, query_data} = result

    flow_name = get_in(query_data, [:data, "createFlow", "flow", "name"])
    assert flow_name == name

    # create message without required atributes
    result = auth_query_gql_by(:create, user, variables: %{"input" => %{}})

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "createFlow", "errors", Access.at(0), "message"]) =~
             "can't be blank"

    # create flow with existing keyword
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => "name_2",
            "keywords" => ["test_keyword"]
          }
        }
      )

    assert {:ok, query_data} = result

    assert "keywords" = get_in(query_data, [:data, "createFlow", "errors", Access.at(0), "key"])

    assert get_in(query_data, [:data, "createFlow", "errors", Access.at(0), "message"]) =~
             "The keyword `testkeyword` was already used in the `Flow Test Name` Flow."
  end

  test "update a flow and test possible scenarios and errors", %{manager: user} do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    name = "Flow Test Name"
    keywords = ["test_keyword"]

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => flow.id,
          "input" => %{"name" => name, "keywords" => keywords}
        }
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateFlow", "flow", "name"])
    assert new_name == name
  end

  test "delete a flow", %{manager: user} do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteFlow", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteFlow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "Publish flow", %{manager: user} do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Language Workflow", organization_id: user.organization_id})

    result = auth_query_gql_by(:publish, user, variables: %{"uuid" => flow.uuid})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "publishFlow", "errors"]) == nil
    assert get_in(query_data, [:data, "publishFlow", "success"]) == true

    result = auth_query_gql_by(:publish, user, variables: %{"uuid" => Ecto.UUID.generate()})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "publishFlow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "Start flow for a contact", %{staff: user} = attrs do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    [contact | _tail] = Contacts.list_contacts(%{filter: attrs})

    result =
      auth_query_gql_by(:contact_flow, user,
        variables: %{"flowId" => flow.id, "contactId" => contact.id}
      )

    assert {:ok, query_data} = result

    # flows dont care about the contact state, we allow each flow node to check
    # and figure out if the operation is permitted
    assert get_in(query_data, [:data, "startContactFlow", "success"]) == true

    # will add test for success with integration tests
  end

  test "Resume flow for a contact", %{staff: user} = attrs do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    [contact | _tail] = Contacts.list_contacts(%{filter: attrs})

    data = %{one: "1", two: "2"} |> Jason.encode!()

    result =
      auth_query_gql_by(:contact_resume, user,
        variables: %{"flowId" => flow.id, "contactId" => contact.id, "result" => data}
      )

    assert {:ok, query_data} = result

    # this flow is not waiting, so it should return error
    # we'll expand test case for a flow waiting soon
    assert get_in(query_data, [:data, "resumeContactFlow", "success"]) == true
    assert !is_nil(get_in(query_data, [:data, "resumeContactFlow", "errors"]))

    # will add test for success with integration tests
    # need to start the flow, setup the context, toggle the DB field
    # and then resume the flow
  end

  test "Start flow for contacts of a group", %{staff: user} do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    group = Fixtures.group_fixture()

    result =
      auth_query_gql_by(:group_flow, user,
        variables: %{"flowId" => flow.id, "groupId" => group.id}
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "startGroupFlow", "success"]) == true
  end

  test "copy a flow and test possible scenarios and errors", %{manager: user} do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    name = "Flow Test Name"
    keywords = ["test_keyword"]

    result =
      auth_query_gql_by(:copy, user,
        variables: %{
          "id" => flow.id,
          "input" => %{"name" => name, "keywords" => keywords}
        }
      )

    assert {:ok, query_data} = result

    assert name == get_in(query_data, [:data, "copyFlow", "flow", "name"])
  end

  test "flow get returns a flow contact",
       %{staff: staff, user: user} do
    State.reset()

    result = auth_query_gql_by(:flow_get, staff, variables: %{"id" => 1})
    assert {:ok, query_data} = result

    assert String.contains?(
             get_in(query_data, [:data, "flowGet", "flow", "name"]),
             "Help Workflow"
           )

    user = Map.put(user, :fingerprint, Ecto.UUID.generate())
    result = auth_query_gql_by(:flow_get, user, variables: %{"id" => 1})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "flowGet", "errors", Access.at(0), "message"]) ==
             "Sorry! You cannot edit the flow right now. It is being edited by \n some name"

    # now release a flow and try again
    result = auth_query_gql_by(:flow_rel, staff, variables: %{})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "flowRelease"]) == nil

    user = Map.put(user, :fingerprint, Ecto.UUID.generate())
    result = auth_query_gql_by(:flow_get, user, variables: %{"id" => 1})
    assert {:ok, query_data} = result

    assert String.contains?(
             get_in(query_data, [:data, "flowGet", "flow", "name"]),
             "Help Workflow"
           )
  end
end
