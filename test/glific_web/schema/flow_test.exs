defmodule GlificWeb.Schema.FlowTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Fixtures,
    Flows,
    Flows.Broadcast,
    Flows.Flow,
    Flows.FlowRevision,
    Flows.MessageBroadcast,
    Groups,
    Repo,
    Seeds.SeedsDev,
    State,
    Templates.InteractiveTemplates
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
  load_gql(:broadcast_stats, GlificWeb.Schema, "assets/gql/flows/broadcast_stats.gql")

  load_gql(
    :terminate_contact_flows,
    GlificWeb.Schema,
    "assets/gql/flows/terminate_contact_flows.gql"
  )

  load_gql(
    :reset_flow_count,
    GlificWeb.Schema,
    "assets/gql/flows/reset_flow_count.gql"
  )

  test "flows field returns list of flows", %{manager: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) > 0

    res =
      flows |> get_in([Access.all(), "name"]) |> Enum.find(fn name -> name == "Help Workflow" end)

    assert res == "Help Workflow"

    [flow | _] = flows
    assert get_in(flow, ["id"]) > 0
  end

  test "flows field returns list of filtered flows", %{manager: user} do
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
      variables: %{
        "input" => %{"name" => "New Flow", "keywords" => "new", "description" => "desc"}
      }
    )

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"status" => "draft"}})
    assert {:ok, query_data} = result
    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) == 1
  end

  test "flows field returns list of flows filtered by isPinned flag", %{manager: user} do
    # Create a new flow
    old_results = auth_query_gql_by(:list, user, variables: %{"filter" => %{"isPinned" => true}})
    assert {:ok, query_data} = old_results
    flows = get_in(query_data, [:data, "flows"])
    old_count = length(flows)

    auth_query_gql_by(:create, user,
      variables: %{
        "input" => %{
          "name" => "New Flow",
          "keywords" => "new",
          "description" => "desc",
          "isPinned" => true
        }
      }
    )

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"isPinned" => true}})
    assert {:ok, query_data} = result
    flows = get_in(query_data, [:data, "flows"])
    ## it depends on the test sequence how many flows have pinned.
    assert length(flows) == old_count + 1
  end

  test "flow field id returns one flow or nil", %{manager: user} do
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

  test "definition field returns one flow definition or nil", %{manager: user} do
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

  test "export flow and the import flow with template when published returns no error",
       %{manager: user} = _attrs do
    [flow | _] = Flows.list_flows(%{filter: %{name: "Import Workflow"}})

    flow_id = flow.id

    Repo.fetch_by(FlowRevision, %{flow_id: flow_id, organization_id: user.organization_id})

    result = auth_query_gql_by(:export_flow, user, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result

    data =
      get_in(query_data, [:data, "exportFlow", "export_data"])
      |> Jason.decode!()

    # Deleting only import flows as importing same flow
    Flows.list_flows(%{id: flow.id})
    |> Enum.each(fn flow -> Flows.delete_flow(flow) end)

    assert length(data["flows"]) > 0
    import_flow = data |> Jason.encode!()
    result = auth_query_gql_by(:import_flow, user, variables: %{"flow" => import_flow})
    assert {:ok, query_data} = result
    import_status = get_in(query_data, [:data, "importFlow", "status", Access.at(0)])
    assert import_status["flowName"] == "Import Workflow"
    assert import_status["status"] == "Successfully imported"

    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Import Workflow", organization_id: user.organization_id})

    result = auth_query_gql_by(:publish, user, variables: %{"uuid" => flow.uuid})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "publishFlow", "errors"]) == nil
    assert get_in(query_data, [:data, "publishFlow", "success"]) == true
  end

  test "export flow and the import flow", %{manager: user} do
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
    Flows.list_flows(%{id: flow.id})
    |> Enum.each(fn flow -> Flows.delete_flow(flow) end)

    # Deleting all existing collections as importing New Contact Flow creates collections
    Groups.list_groups(%{})
    |> Enum.each(fn group -> Groups.delete_group(group) end)

    # Deleting all existing interactive templates as importing New Contact Flow creates interactive templates
    InteractiveTemplates.list_interactives(%{})
    |> Enum.each(fn interactive_template ->
      InteractiveTemplates.delete_interactive_template(interactive_template)
    end)

    import_flow = data |> Jason.encode!()
    result = auth_query_gql_by(:import_flow, user, variables: %{"flow" => import_flow})
    assert {:ok, query_data} = result
    import_status = get_in(query_data, [:data, "importFlow", "status", Access.at(0)])
    assert import_status["flowName"] == "New Contact Workflow"
    assert import_status["status"] == "Successfully imported"
    [group | _] = Groups.list_groups(%{filter: %{label: "Optin contacts"}})
    assert group.label == "Optin contacts"

    [interactive_template | _] =
      InteractiveTemplates.list_interactives(%{filter: %{label: "Optin template"}})

    assert interactive_template.label == "Optin template"
  end

  test "create a flow and test possible scenarios and errors", %{manager: user} do
    name = "Flow Test Name"
    keywords = ["test_keyword", "test_keyword_2"]
    description = "test description"

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"name" => name, "keywords" => keywords, "description" => description}
        }
      )

    assert {:ok, query_data} = result

    flow_name = get_in(query_data, [:data, "createFlow", "flow", "name"])
    assert flow_name == name

    # create message without required attributes
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
            "keywords" => ["test_keyword"],
            "description" => "desc_2"
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
    description = "test description"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => flow.id,
          "input" => %{"name" => name, "keywords" => keywords, "description" => description}
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

  test "Start flow for a contact", %{manager: user} = attrs do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    [contact | _tail] = Contacts.list_contacts(%{filter: attrs})

    result =
      auth_query_gql_by(:contact_flow, user,
        variables: %{"flowId" => flow.id, "contactId" => contact.id}
      )

    assert {:ok, query_data} = result

    # flows don't care about the contact state, we allow each flow node to check
    # and figure out if the operation is permitted
    assert get_in(query_data, [:data, "startContactFlow", "success"]) == true

    # will add test for success with integration tests
  end

  test "Resume flow for a contact", %{manager: user} = attrs do
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

  test "Terminate all flows for a contact", %{manager: user} = attrs do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    [contact | _tail] = Contacts.list_contacts(%{filter: attrs})

    result =
      auth_query_gql_by(:terminate_contact_flows, user,
        variables: %{"flowId" => flow.id, "contactId" => contact.id}
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "terminateContactFlows", "success"]) == true
  end

  test "Reset all the counts for a flows", %{manager: user} do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Test Workflow", organization_id: user.organization_id})

    result = auth_query_gql_by(:reset_flow_count, user, variables: %{"flowId" => flow.id})

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "resetFlowCount", "success"]) == true
  end

  test "Start flow for contacts of a group", %{manager: user} do
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
    description = "test description"

    result =
      auth_query_gql_by(:copy, user,
        variables: %{
          "id" => flow.id,
          "input" => %{"name" => name, "keywords" => keywords, "description" => description}
        }
      )

    assert {:ok, query_data} = result

    assert name == get_in(query_data, [:data, "copyFlow", "flow", "name"])
  end

  test "flow get returns a flow contact",
       %{manager: staff, user: user} do
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
             "This flow is being edited by some name right now!"

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

  test "message broadcast stats", %{glific_admin: glific_admin} = attrs do
    [flow | _tail] = Flows.list_flows(%{filter: attrs})
    group = Fixtures.group_fixture()

    [contact, contact2 | _] =
      Contacts.list_contacts(%{
        filter: %{organization_id: attrs.organization_id, name: "Glific Simulator"}
      })

    Groups.create_contact_group(%{
      group_id: group.id,
      contact_id: contact.id,
      organization_id: attrs.organization_id
    })

    Groups.create_contact_group(%{
      group_id: group.id,
      contact_id: contact2.id,
      organization_id: attrs.organization_id
    })

    {:ok, flow} = Flows.start_group_flow(flow, [group.id])

    assert {:ok, message_broadcast} =
             Repo.fetch_by(MessageBroadcast, %{
               group_id: group.id,
               flow_id: flow.id
             })

    assert message_broadcast.completed_at == nil

    # lets sleep for 3 seconds, to ensure that messages have been delivered
    Broadcast.execute_broadcasts(attrs.organization_id)
    Process.sleep(3_000)

    result =
      auth_query_gql_by(:broadcast_stats, glific_admin,
        variables: %{
          "messageBroadcastId" => message_broadcast.id
        }
      )

    # test case should be checking the message categories as well
    # but currently as bsp_status is returning null, msg_categories is not populated. Will come back at later time
    assert {:ok, query_data} = result
    broadcast_stats = get_in(query_data, [:data, "broadcastStats"])
    broadcast_map = Jason.decode!(broadcast_stats)
    assert true == Map.has_key?(broadcast_map, "failed")
    assert true == Map.has_key?(broadcast_map, "msg_categories")
    assert true == Map.has_key?(broadcast_map, "pending")
    assert true == Map.has_key?(broadcast_map, "success")
  end
end
