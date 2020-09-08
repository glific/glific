defmodule Glific.Flows.FlowContextTest do
  use Glific.DataCase, async: true

  alias Glific.Fixtures

  alias Glific.Flows.{
    Action,
    Category,
    Flow,
    FlowContext,
    Node
  }

  @valid_attrs %{
    flow_id: 1,
    flow_uuid: Ecto.UUID.generate(),
    uuid_map: %{},
    node_uuid: Ecto.UUID.generate()
  }

  def flow_context_fixture(attrs \\ %{}) do
    {:ok, flow_context} =
      attrs
      |> Map.put(:contact_id, Fixtures.contact_fixture().id)
      |> Enum.into(@valid_attrs)
      |> FlowContext.create_flow_context()

    flow_context
  end

  test "create_flow_context/1 will create a new flow context" do
    # create a simple flow context
    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: Fixtures.contact_fixture().id,
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        uuid_map: %{}
      })

    assert context.id != nil
  end

  test "reset_context/1 will reset the context" do
    node = %Node{uuid: Ecto.UUID.generate()}

    json = %{
      "uuid" => Ecto.UUID.generate(),
      "type" => "enter_flow",
      "flow" => %{"uuid" => Ecto.UUID.generate()}
    }

    {_, uuid_map} = Action.process(json, %{}, node)

    {:ok, context_2} =
      FlowContext.create_flow_context(%{
        contact_id: Fixtures.contact_fixture().id,
        flow_id: 1,
        flow_uuid: json["flow"]["uuid"],
        uuid_map: uuid_map
      })

    FlowContext.reset_context(context_2)
  end

  test "update_flow_context/2 will update the UUID for the current context node" do
    flow_context = flow_context_fixture()
    uuid = Ecto.UUID.generate()
    {:ok, flow_context_2} = FlowContext.update_flow_context(flow_context, %{node_uuid: uuid})
    assert flow_context_2.node_uuid == uuid
  end

  test "update_results/2 will update the results object for the context" do
    flow_context = flow_context_fixture()
    json = %{"uuid" => "UUID 1", "exit_uuid" => "UUID 2", "name" => "Default Category"}
    {category, _uuid_map} = Category.process(json, %{})
    FlowContext.update_results(flow_context, "test_key", "test_input", category.name)
    flow_context = Glific.Repo.get!(FlowContext, flow_context.id)

    assert flow_context.results["test_key"] == %{
             "input" => "test_input",
             "category" => category.name
           }
  end

  test "set_node/2 will set the node object for the context" do
    flow_context = flow_context_fixture()
    node = %Node{uuid: Ecto.UUID.generate()}
    flow_context = FlowContext.set_node(flow_context, node)
    assert flow_context.node == node
  end

  test "init_context/3 will initaite a flow context",
       %{organization_id: organization_id} = attrs do
    [flow | _tail] = Glific.Flows.list_flows(%{filter: attrs})
    [keyword | _] = flow.keywords
    flow = Flow.get_loaded_flow(%{keyword: keyword, organization_id: organization_id})
    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact)
    assert flow_context.id != nil
  end

  test "execute an context for a empty node with return the error" do
    flow_context = flow_context_fixture()
    assert {:error, _message} = FlowContext.execute(flow_context, [])
  end

  test "execute an context should return ok tuple", %{organization_id: organization_id} = attrs do
    [flow | _tail] = Glific.Flows.list_flows(%{filter: attrs})
    [keyword | _] = flow.keywords
    flow = Flow.get_loaded_flow(%{keyword: keyword, organization_id: organization_id})
    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact)
    assert {:ok, _, _} = FlowContext.execute(flow_context, ["Test"])
  end

  test "active_context/1 will return the current context for contact" do
    flow_context = flow_context_fixture()
    flow_context_2 = FlowContext.active_context(flow_context.contact_id)
    assert flow_context.id == flow_context_2.id
  end

  test "load_context/2 will load all the nodes and actions in memory for the context",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(%{keyword: "help", organization_id: organization_id})
    [node | _tail] = flow.nodes
    flow_context = flow_context_fixture(%{node_uuid: node.uuid})
    flow_context = FlowContext.load_context(flow_context, flow)
    assert flow_context.uuid_map == flow.uuid_map
  end

  test "step_forward/2 will set the context to next node ",
       %{organization_id: organization_id} = _attrs do
    flow = Flow.get_loaded_flow(%{keyword: "help", organization_id: organization_id})
    [node | _tail] = flow.nodes
    flow_context = flow_context_fixture(%{node_uuid: node.uuid})
    flow_context = FlowContext.load_context(flow_context, flow)
    assert {:ok, _map} = FlowContext.step_forward(flow_context, "help")
  end

  test "get_result_value/2 will return the result value for a key" do
    flow_context = flow_context_fixture()
    json = %{"uuid" => "UUID 1", "exit_uuid" => "UUID 2", "name" => "Default Category"}
    {category, _uuid_map} = Category.process(json, %{})
    FlowContext.update_results(flow_context, "test_key", "test_input", category.name)
    flow_context = Glific.Repo.get!(FlowContext, flow_context.id)

    assert FlowContext.get_result_value(flow_context, "@results.test_key") ==
             %{"category" => "Default Category", "input" => "test_input"}
  end
end
