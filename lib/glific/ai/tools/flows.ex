defmodule Glific.AI.Tools.Flows do
  @moduledoc """
  Reads about flows: which exist, how one is built, where contacts are sitting
  inside it, and what its webhook calls returned.

  Together these answer the question staff actually ask — *"why isn't my flow
  working"* — without anyone having to open the flow editor.
  """

  import Ecto.Query

  alias Glific.{
    Flows,
    Flows.FlowContext,
    Flows.FlowCount,
    Flows.FlowLabel,
    Flows.FlowResult,
    Flows.FlowRevision,
    Flows.WebhookLog,
    Repo,
    Sheets
  }

  @behaviour Glific.AI.Tool

  @snippet 120

  @impl Glific.AI.Tool
  def specs do
    [
      %{
        name: "list_flows",
        description: """
        Lists the flows in this organisation, with their ids, names and keywords.
        Use this first whenever a question mentions a flow by name, to find its id.
        Optionally filter by a partial name.
        """,
        parameters: [
          name: [type: :string, doc: "Only return flows whose name contains this text"],
          limit: [type: :pos_integer, default: 25, doc: "How many flows to return, at most 100"]
        ]
      },
      %{
        name: "get_flow",
        description: """
        Describes one flow's structure: each node, the messages it sends, the
        questions it asks and where its exits lead. Use it to explain what a flow
        does or to find where it might go wrong. Call list_flows first if you only
        know the flow's name.
        """,
        parameters: [
          flow_id: [type: :pos_integer, required: true, doc: "The flow's id, from list_flows"],
          status: [
            type: {:in, ["published", "draft"]},
            default: "published",
            doc: "Which revision to describe"
          ]
        ]
      },
      %{
        name: "flow_status",
        description: """
        Shows where contacts currently are inside a flow: how many are waiting at
        each node, how many completed, and how many were stopped and why. Use this
        to diagnose a flow that is not behaving as expected. Pair the node uuids
        with get_flow to see which message each one corresponds to.
        """,
        parameters: [
          flow_id: [type: :pos_integer, required: true, doc: "The flow's id, from list_flows"]
        ]
      },
      %{
        name: "flow_results",
        description: """
        Lists what a flow collected from contacts: the answers saved against each
        result name. Use this to check whether a question in a flow is actually
        capturing what it should.
        """,
        parameters: [
          flow_id: [type: :pos_integer, required: true, doc: "The flow's id, from list_flows"],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "flow_counts",
        description: """
        Counts how many times each node and each exit of a flow has been taken.
        Use this to find where contacts drop off: a node with far fewer counts
        than the one before it is where they are being lost.
        """,
        parameters: [
          flow_id: [type: :pos_integer, required: true, doc: "The flow's id, from list_flows"]
        ]
      },
      %{
        name: "list_flow_labels",
        description: """
        Lists the flow labels defined in this organisation. Flows tag messages
        with these, and message_history reports them, so this is how a label
        named in a question is checked against what exists.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      },
      %{
        name: "list_sheets",
        description: """
        Lists the Google Sheets this organisation reads from or writes to in
        flows, with their sync status and any failure reason. A flow that reads
        stale or missing sheet data usually shows up here first.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "list_webhook_logs",
        description: """
        Lists recent webhook calls made from flows, with the URL, status code and
        any error. Use this when a flow that calls a webhook is misbehaving, to
        see whether the call failed or returned something unexpected.
        """,
        parameters: [
          status_code: [type: :integer, doc: "Only calls that returned this HTTP status"],
          url: [type: :string, doc: "Only calls whose URL contains this text"],
          limit: [type: :pos_integer, default: 20, doc: "How many to return, at most 50"]
        ]
      }
    ]
  end

  @impl Glific.AI.Tool
  def run("list_flows", args) do
    filter = if args[:name], do: %{name: args[:name]}, else: %{}

    flows =
      %{filter: filter, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> Flows.list_flows()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          keywords: &1.keywords,
          is_active: &1.is_active,
          is_background: &1.is_background,
          last_changed_at: &1.last_changed_at
        }
      )

    {:ok, flows}
  end

  def run("get_flow", %{flow_id: flow_id} = args) do
    with {:ok, flow} <- fetch_flow(flow_id),
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
    end
  end

  def run("flow_status", %{flow_id: flow_id}) do
    with {:ok, flow} <- fetch_flow(flow_id) do
      {:ok, %{flow: %{id: flow.id, name: flow.name}, contacts: status(flow_id)}}
    end
  end

  def run("list_webhook_logs", args) do
    filter =
      %{}
      |> maybe_put(:status_code, args[:status_code])
      |> maybe_put(:url, args[:url])

    logs =
      %{filter: filter, opts: %{limit: min(args[:limit], 50), offset: 0, order: :desc}}
      |> WebhookLog.list_webhook_logs()
      |> Enum.map(
        &%{
          id: &1.id,
          url: &1.url,
          method: &1.method,
          status_code: &1.status_code,
          error: &1.error,
          flow_id: &1.flow_id,
          inserted_at: &1.inserted_at
        }
      )

    {:ok, logs}
  end

  def run("flow_results", %{flow_id: flow_id} = args) do
    with {:ok, _flow} <- fetch_flow(flow_id) do
      results =
        FlowResult
        |> where([r], r.flow_id == ^flow_id)
        |> order_by([r], desc: r.inserted_at)
        |> limit(^min(args[:limit], 100))
        |> select([r], %{
          contact_id: r.contact_id,
          flow_version: r.flow_version,
          results: r.results,
          inserted_at: r.inserted_at
        })
        |> Repo.all()

      {:ok, results}
    end
  end

  def run("flow_counts", %{flow_id: flow_id}) do
    with {:ok, flow} <- fetch_flow(flow_id) do
      counts =
        flow.uuid
        |> FlowCount.get_flow_count_list()
        |> Enum.map(
          &%{
            uuid: &1.uuid,
            type: &1.type,
            count: &1.count,
            destination_uuid: &1.destination_uuid
          }
        )

      {:ok, %{flow: %{id: flow.id, name: flow.name}, counts: counts}}
    end
  end

  def run("list_flow_labels", args) do
    labels =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0, order: :asc}}
      |> FlowLabel.list_flow_labels()
      |> Enum.map(&%{id: &1.id, name: &1.name, type: &1.type})

    {:ok, labels}
  end

  def run("list_sheets", args) do
    sheets =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> Sheets.list_sheets()
      |> Enum.map(
        &%{
          id: &1.id,
          label: &1.label,
          url: &1.url,
          type: &1.type,
          is_active: &1.is_active,
          sync_status: &1.sync_status,
          failure_reason: &1.failure_reason,
          last_synced_at: &1.last_synced_at,
          sheet_data_count: &1.sheet_data_count
        }
      )

    {:ok, sheets}
  end

  @spec fetch_flow(non_neg_integer()) :: {:ok, Flows.Flow.t()} | {:error, String.t()}
  defp fetch_flow(flow_id) do
    case Flows.fetch_flow(flow_id) do
      {:ok, flow} -> {:ok, flow}
      {:error, _} -> {:error, "No flow with id #{flow_id} exists in this organisation."}
    end
  end

  # A flow that exists but has never been published is a different answer from a
  # flow that does not exist, and the model needs to be told which it is.
  @spec definition(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp definition(flow_id, status) do
    FlowRevision
    |> where([r], r.flow_id == ^flow_id and r.status == ^status)
    |> order_by([r], desc: r.version)
    |> limit(1)
    |> select([r], r.definition)
    |> Repo.one()
    |> case do
      nil ->
        {:error,
         "Flow #{flow_id} exists but has no #{status} revision. " <>
           ~s(Try status "draft" if you were looking at the published version.)}

      definition ->
        {:ok, definition}
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

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(filter, _key, nil), do: filter
  defp maybe_put(filter, key, value), do: Map.put(filter, key, value)
end
