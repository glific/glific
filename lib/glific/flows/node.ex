defmodule Glific.Flows.Node do
  @moduledoc """
  The Node object which encapsulates one node in a given flow
  """
  alias __MODULE__

  use Ecto.Schema
  import GlificWeb.Gettext

  alias Glific.{
    Flows,
    Messages.Message,
    Metrics
  }

  alias Glific.Flows.{
    Action,
    Exit,
    Flow,
    FlowContext,
    Router
  }

  @required_fields [:uuid, :actions, :exits]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | nil,
          is_terminal: boolean() | false,
          actions: [Action.t()] | [],
          exits: [Exit.t()] | [],
          router: Router.t() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID
    field :flow_id, :integer
    field :flow_uuid, Ecto.UUID

    field :is_terminal, :boolean, default: false

    embeds_one :flow, Flow

    embeds_many :actions, Action
    embeds_many :exits, Exit
    embeds_one :router, Router
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Flow.t()) :: {Node.t(), map()}
  def process(json, uuid_map, flow) do
    Flows.check_required_fields(json, @required_fields)

    node = %Node{
      uuid: json["uuid"],
      flow_uuid: flow.uuid,
      flow_id: flow.id
    }

    {actions, uuid_map} =
      Flows.build_flow_objects(
        json["actions"],
        uuid_map,
        &Action.process/3,
        node
      )

    node = Map.put(node, :actions, actions)

    {exits, uuid_map} =
      Flows.build_flow_objects(
        json["exits"],
        uuid_map,
        &Exit.process/3,
        node
      )

    node =
      node
      |> Map.put(:exits, exits)
      |> Map.put(:is_terminal, is_terminal?(exits))

    {node, uuid_map} =
      if Map.has_key?(json, "router") do
        {router, uuid_map} = Router.process(json["router"], uuid_map, node)
        node = Map.put(node, :router, router)

        {
          node,
          Map.put(uuid_map, node.uuid, {:node, node})
        }
      else
        {
          node,
          Map.put(uuid_map, node.uuid, {:node, node})
        }
      end

    {node, uuid_map}
  end

  @spec is_terminal?(list()) :: boolean()
  defp is_terminal?(exits),
    do:
      exits
      |> Enum.all?(fn e -> is_nil(e.destination_node_uuid) end)

  @doc """
  If the node has a router component, and the flow has enabled us to fix
  other/no response pathways, do the needful for that node
  """
  @spec fix_node(Node.t(), Flow.t(), map()) :: {Node.t(), map()}
  def fix_node(%{router: nil} = node, _flow, uuid_map), do: {node, uuid_map}

  def fix_node(node, %{respond_other: false, respond_no_response: false}, uuid_map),
    do: {node, uuid_map}

  def fix_node(node, flow, uuid_map) do
    {exits, uuid_map} = fix_exits(node.exits, node.router, flow, uuid_map)

    # we have no idea of the list was reversed zero, once or twice
    # this depends on the various boolean conditions, and hence the equality checks
    # for both the original and the reversed list
    if node.exits == exits || node.exits == Enum.reverse(exits) do
      {node, uuid_map}
    else
      node = Map.put(node, :exits, exits)

      {
        node,
        Map.put(uuid_map, node.uuid, {:node, node})
      }
    end
  end

  @spec fix_exits([Exit.t()], Router.t(), Flow.t(), map()) :: {[Exit.t()], map()}
  defp fix_exits(
         exits,
         router,
         %{respond_other: other, respond_no_response: no_response},
         uuid_map
       ),
       do:
         {exits, uuid_map}
         |> fix_exit(router.other_exit_uuid, other)
         |> fix_exit(router.no_response_exit_uuid, no_response)

  @spec fix_exit({[Exit.t()], map()}, Ecto.UUID.t(), boolean) :: {[Exit.t()], map()}
  defp fix_exit({exits, uuid_map}, _exit_uuid, false), do: {exits, uuid_map}
  defp fix_exit({exits, uuid_map}, nil, _exit_flag), do: {exits, uuid_map}

  defp fix_exit({exits, uuid_map}, exit_uuid, _exit_flag) do
    Enum.reduce(
      exits,
      {[], uuid_map},
      fn e, {exits, uuid_map} ->
        lookup = uuid_map[{:reverse, e.node_uuid}]

        if e.uuid == exit_uuid &&
             e.destination_node_uuid == nil &&
             lookup != nil do
          e = Map.put(e, :destination_node_uuid, elem(lookup, 1))
          uuid_map = Map.put(uuid_map, e.uuid, {:exit, e})
          {[e | exits], uuid_map}
        else
          {[e | exits], uuid_map}
        end
      end
    )
  end

  @doc """
  Validate a node and all its children
  """
  @spec validate(Node.t(), Keyword.t(), map()) :: Keyword.t()
  def validate(node, errors, flow) do
    errors =
      node.actions
      |> Enum.reduce(
        errors,
        &Action.validate(&1, &2, flow)
      )

    errors =
      node.exits
      |> Enum.reduce(
        errors,
        &Exit.validate(&1, &2, flow)
      )

    if node.router,
      do: Router.validate(node.router, errors, flow),
      else: errors
  end

  @doc """
  Wrapper function to bump the count of the node using our
  metrics subsystem
  """
  @spec bump_count(Node.t(), FlowContext.t()) :: any
  def bump_count(node, context) do
    # update the flow count
    Metrics.bump(%{
      uuid: node.uuid,
      flow_id: node.flow_id,
      flow_uuid: node.flow_uuid,
      organization_id: context.organization_id,
      type: "node"
    })
  end

  @doc """
  Wrapper function to abort and clean things up when we detect an infinite loop
  """
  @spec infinite_loop(FlowContext.t(), String.t()) ::
          {:ok, map(), any()}
  def infinite_loop(context, body) do
    message = "Infinite loop detected, body: #{body}. Resetting flows"
    context = FlowContext.reset_all_contexts(context, message)

    # at some point soon, we should change action signatures to allow error
    {:ok, context, []}
  end

  @node_map_key {__MODULE__, :node_map}
  @node_max_count 5

  @doc false
  @spec reset_node_map() :: any()
  def reset_node_map,
    do: Process.put(@node_map_key, %{})

  # stores a global map of how many times we process each node
  # based on its uuid
  @spec check_infinite_loop(Node.t(), FlowContext.t()) :: boolean()
  defp check_infinite_loop(node, context) do
    node_map = Process.get(@node_map_key, %{})
    count = Map.get(node_map, {context.id, node.uuid}, 0)
    Process.put(@node_map_key, Map.put(node_map, {context.id, node.uuid}, count + 1))

    count > @node_max_count
  end

  @wait_for ["wait_for_time", "wait_for_result"]

  @doc """
  Execute a node, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(atom() | Node.t(), atom() | FlowContext.t(), [Message.t()]) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  def execute(node, context, messages) do
    # if node has an action, execute the first action
    :telemetry.execute(
      [:glific, :flow, :node],
      %{},
      %{
        id: node.id,
        context_id: context.id,
        flow_id: context.flow_id,
        contact_id: context.contact_id
      }
    )

    cond do
      # check if we are looping forever, if so abort early
      check_infinite_loop(node, context) ->
        infinite_loop(context, node.uuid)

      # we special case wait for time, since it has a router, which basically
      # is an empty shell and just exits along the normal path
      !Enum.empty?(node.actions) && hd(node.actions).type in @wait_for ->
        execute_node_actions(node, context, messages)

      # if both are non-empty, it means that we have either a
      #   * sub-flow option
      #   * calling a web hook
      !Enum.empty?(node.actions) && !is_nil(node.router) ->
        execute_node_router(node, context, messages)

      !Enum.empty?(node.actions) ->
        execute_node_actions(node, context, messages)

      !is_nil(node.router) ->
        Router.execute(node.router, context, messages)

      true ->
        {:error, dgettext("errors", "Unsupported node type")}
    end
  end

  @spec execute_node_router(Node.t(), FlowContext.t(), [Message.t()]) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  defp execute_node_router(node, context, messages) do
    # need a better way to figure out if we should handle router or action
    # this is a hack for now
    action = hd(node.actions)

    if messages != [] and
         hd(messages).clean_body in ["completed", "expired", "success", "failure"] do
      Router.execute(node.router, context, messages)
    else
      Action.execute(action, context, messages)
    end
  end

  @spec execute_node_actions(Node.t(), FlowContext.t(), [Message.t()]) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  defp execute_node_actions(node, context, messages) do
    bump_count(node, context)

    # we need to execute all the actions (nodes can have multiple actions)
    result =
      Enum.reduce(
        node.actions,
        {:ok, context, messages},
        fn action, acc ->
          {:ok, context, messages} = acc
          Action.execute(action, context, messages)
        end
      )

    case elem(result, 0) do
      :error ->
        result

      :ok ->
        {_status, context, messages} = result
        Exit.execute(hd(node.exits), context, messages)

      :wait ->
        {_status, context, messages} = result
        {:ok, context, messages}
    end
  end
end
