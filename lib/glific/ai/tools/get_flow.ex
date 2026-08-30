defmodule Glific.AI.Tools.GetFlow do
  @moduledoc """
  Describes one flow: its nodes, what each sends or asks, and where exits lead.

  A summary rather than the raw definition, which is mostly editor layout and
  localisation and can run to hundreds of kilobytes.
  """

  @behaviour Glific.AI.Tool

  import Ecto.Query

  alias Glific.{Flows, Flows.FlowRevision, Repo}

  @snippet 120

  @impl Glific.AI.Tool
  def name, do: "get_flow"

  @impl Glific.AI.Tool
  def description do
    """
    Describes one flow's structure: each node, the messages it sends, the
    questions it asks and where its exits lead. Use it to explain what a flow
    does or to find where it might go wrong. Call list_flows first if you only
    know the flow's name.
    """
  end

  @impl Glific.AI.Tool
  def parameters do
    [
      flow_id: [type: :pos_integer, required: true, doc: "The flow's id, from list_flows"],
      status: [
        type: {:in, ["published", "draft"]},
        default: "published",
        doc: "Which revision to describe"
      ]
    ]
  end

  @impl Glific.AI.Tool
  def run(%{flow_id: flow_id} = args) do
    with {:ok, flow} <- Flows.fetch_flow(flow_id),
         {:ok, definition} <- definition(flow_id, args[:status]) do
      {:ok,
       %{
         id: flow.id,
         name: flow.name,
         keywords: flow.keywords,
         is_active: flow.is_active,
         revision: args[:status],
         nodes: Enum.map(Map.get(definition, "nodes", []), &node_summary/1)
       }}
    else
      {:error, _} ->
        {:error, "No flow with id #{flow_id} exists in this organisation."}
    end
  end

  @spec definition(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, term()}
  defp definition(flow_id, status) do
    FlowRevision
    |> where([r], r.flow_id == ^flow_id and r.status == ^status)
    |> order_by([r], desc: r.version)
    |> limit(1)
    |> select([r], r.definition)
    |> Repo.one()
    |> case do
      nil -> {:error, :no_revision}
      definition -> {:ok, definition}
    end
  end

  @spec node_summary(map()) :: map()
  defp node_summary(node) do
    %{
      uuid: node["uuid"],
      actions: node |> Map.get("actions", []) |> Enum.map(&action_summary/1),
      waits_for_reply: is_map(node["router"]),
      router: router_summary(node["router"]),
      exits: node |> Map.get("exits", []) |> Enum.map(& &1["destination_uuid"])
    }
  end

  @spec action_summary(map()) :: map()
  defp action_summary(action) do
    %{type: action["type"], text: truncate(action["text"])}
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @spec router_summary(map() | nil) :: map() | nil
  defp router_summary(nil), do: nil

  defp router_summary(router) do
    %{
      type: router["type"],
      categories: router |> Map.get("categories", []) |> Enum.map(& &1["name"])
    }
  end

  @spec truncate(String.t() | nil) :: String.t() | nil
  defp truncate(nil), do: nil

  defp truncate(text) when is_binary(text) do
    if String.length(text) > @snippet, do: String.slice(text, 0, @snippet) <> "…", else: text
  end

  defp truncate(_), do: nil
end
