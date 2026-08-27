defmodule Glific.AI.Tools.FlowStatus do
  @moduledoc """
  Reports where contacts currently sit inside a flow.

  This is the single best answer to *"why isn't my flow working"* — it shows
  contacts piled up at one node, or killed contexts and the reason. It has no
  GraphQL query, so it is not reachable through the public API at all; running
  in-process is what makes it available.
  """

  @behaviour Glific.AI.Tool

  import Ecto.Query

  alias Glific.{Flows, Flows.FlowContext, Repo}

  @impl Glific.AI.Tool
  def name, do: "flow_status"

  @impl Glific.AI.Tool
  def description do
    """
    Shows where contacts currently are inside a flow: how many are waiting at
    each node, how many completed, and how many were stopped and why. Use this
    to diagnose a flow that is not behaving as expected. Pair the node uuids
    with get_flow to see which message each one corresponds to.
    """
  end

  @impl Glific.AI.Tool
  def parameters do
    [
      flow_id: [type: :pos_integer, required: true, doc: "The flow's id, from list_flows"]
    ]
  end

  @impl Glific.AI.Tool
  def run(%{flow_id: flow_id}) do
    case Flows.fetch_flow(flow_id) do
      {:ok, flow} -> {:ok, %{flow: %{id: flow.id, name: flow.name}, contacts: status(flow_id)}}
      {:error, _} -> {:error, "No flow with id #{flow_id} exists in this organisation."}
    end
  end

  @spec status(non_neg_integer()) :: map()
  defp status(flow_id) do
    %{
      waiting_at_node: waiting(flow_id),
      completed: count(flow_id, dynamic([c], not is_nil(c.completed_at))),
      stopped: stopped(flow_id)
    }
  end

  @spec waiting(non_neg_integer()) :: [map()]
  defp waiting(flow_id) do
    FlowContext
    |> where([c], c.flow_id == ^flow_id)
    |> where([c], is_nil(c.completed_at) and c.is_killed == false)
    |> group_by([c], c.node_uuid)
    |> select([c], %{node_uuid: c.node_uuid, contacts: count(c.id)})
    |> order_by([c], desc: count(c.id))
    |> limit(20)
    |> Repo.all()
  end

  @spec stopped(non_neg_integer()) :: [map()]
  defp stopped(flow_id) do
    FlowContext
    |> where([c], c.flow_id == ^flow_id and c.is_killed == true)
    |> group_by([c], c.reason)
    |> select([c], %{reason: c.reason, contacts: count(c.id)})
    |> Repo.all()
  end

  @spec count(non_neg_integer(), Ecto.Query.dynamic_expr()) :: non_neg_integer()
  defp count(flow_id, condition) do
    FlowContext
    |> where([c], c.flow_id == ^flow_id)
    |> where(^condition)
    |> Repo.aggregate(:count)
  end
end
