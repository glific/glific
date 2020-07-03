defmodule Glific.Flows.First do
  @moduledoc """
  Random experiments on how to process flows emitted
  by nyaruka floweditor
  """

  @test_file "/json/help.json"

  alias Glific.Flows.{
    Action,
    Case,
    Category,
    Exit,
    Flow,
    Node,
    Router
  }

  @doc """
  iex module for us to interact with our actions and events
  """
  @spec init() :: nil
  def init do
    File.read!(__DIR__ <> @test_file)
    |> Jason.decode!()
    # lets get rid of stuff we domnt use
    |> Map.delete("_ui")
    |> process_flow()
    |> uuid_map()
    |> Enum.sort(fn {_k1, v1}, {_k2, v2} -> v1 < v2 end)
  end

  def uuid_map(%Flow{} = flow) do
    flow.nodes
    |> Enum.reduce(
      %{flow.uuid => :flow},
      fn n, acc -> Map.merge(acc, uuid_map(n)) end
    )
  end
  def uuid_map(%Node{} = node) do
    node.actions ++ node.exits ++ [node.router]
    |> Enum.reduce(
      %{node.uuid => :node},
      fn a, acc -> Map.merge(acc, uuid_map(a)) end
      )
  end
  def uuid_map(%Router{} = router) do
    Enum.reduce(
      router.cases ++ router.categories,
      %{},
      fn a, acc -> Map.merge(acc, uuid_map(a)) end)
  end
  def uuid_map(%Action{} = action), do: %{action.uuid => :action}
  def uuid_map(%Exit{} = exit), do: %{exit.uuid => :exit}
  def uuid_map(%Case{} = case), do: %{case.uuid => :case}
  def uuid_map(%Category{} = category), do: %{category.uuid => :category}
  def uuid_map(nil), do: %{}

  def process_flow(json) do
    flow = %Flow{
      uuid: json["uuid"],
      language: json["language"],
      name: json["name"]
    }

    Map.put(
      flow,
      :nodes,
      Enum.map(
        json["nodes"],
        fn node -> process_node(node, flow) end
      )
    )
  end

  def process_node(json, flow) do
    node = %Node{
      uuid: json["uuid"],
      flow_uuid: flow.uuid
    }

    node =
      Map.put(
        node,
        :actions,
        Enum.map(
          json["actions"],
          fn action -> process_action(action, node) end
        )
      )

    node =
      Map.put(
        node,
        :exits,
        Enum.map(
          json["exits"],
          fn exit -> process_exit(exit, node) end
        )
      )

    Map.put(
      node,
      :router,
      if(Map.has_key?(json, "router"), do: process_router(json["router"], node), else: nil)
    )
  end

  def process_action(%{"type" => type} = json, node) when type == "enter_flow" do
    %Action{
      uuid: json["uuid"],
      node_uuid: node.uuid,
      type: json["type"],
      enter_flow_uuid: json["flow"]["uuid"]
    }
  end

  def process_action(json, node) do
    %Action{
      uuid: json["uuid"],
      node_uuid: node.uuid,
      text: json["text"],
      type: json["type"],
      quick_replies: json["quick_replies"]
    }
  end

  def process_exit(json, node) do
    %Exit{
      uuid: json["uuid"],
      node_uuid: node.uuid,
      destination_node_uuid: json["destination_uuid"]
    }
  end

  def process_router(json, node) do
    router = %Router{
      # A router does not have a uuid, since it is attached to a node (optionally)
      # uuid: json["uuid"],
      node_uuid: node.uuid,
      type: json["type"],
      operand: json["operand"],
      result_name: json["result_name"],
      wait_type: json["wait"]["type"]
    }

    router =
      Map.put(
        router,
        :categories,
        Enum.map(
          json["categories"],
          fn c -> process_category(c, router) end
        )
      )
      # we should check that this category does exist and for FK checks etc, before adding to DB
      # we can only assign this after the category is created
      |> Map.put(
        :default_category_uuid,
        json["default_category_uuid"]
      )

    Map.put(
      router,
      :cases,
      Enum.map(
        json["cases"],
        fn c -> process_case(c, router) end
      )
    )
  end

  def process_category(json, router) do
    %Category{
      uuid: json["uuid"],
      router_uuid: router.uuid,
      exit_uuid: json["exit_uuid"],
      name: json["name"]
    }
  end

  def process_case(json, router) do
    %Case{
      uuid: json["uuid"],
      router_uuid: router.uuid,
      category_uuid: json["category_uuid"],
      type: json["type"],
      arguments: json["arguments"]
    }
  end
end
