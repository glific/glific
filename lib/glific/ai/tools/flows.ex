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
    Flows.FlowResult,
    Flows.FlowRevision,
    Flows.WebhookLog,
    Repo,
    Sheets,
    Sheets.SheetData
  }

  @behaviour Glific.AI.Tool

  @snippet 120
  @max_nodes 500

  @doc "Every flow lookup this module offers."
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
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
        Describes one flow: each node, the messages it sends, the questions it
        asks and where its exits lead. Call list_flows first if you only know the
        flow's name.

        On its own this answers "what does this flow do". Add `include` to answer
        why it is misbehaving, asking only for the parts the question needs:

          * "contacts" — how many sit at each node, completed, or were stopped and why
          * "counts" — how often each node and exit was taken, which is where drop-off shows
          * "results" — the answers the flow collected from contacts
          * "webhooks" — the webhook calls this flow made, with status codes and errors

        For "why is my flow not working", ask for all four.

        A flow larger than `limit` comes back with its nodes marked as truncated,
        so raise the limit before concluding anything about a flow you have only
        partly seen.
        """,
        parameters: [
          flow_id: [type: :pos_integer, required: true, doc: "The flow's id, from list_flows"],
          status: [
            type: {:in, ["published", "draft"]},
            default: "published",
            doc: "Which revision to describe"
          ],
          include: [
            type: {:list, {:in, ["contacts", "counts", "results", "webhooks"]}},
            default: [],
            doc: "Extra detail to return alongside the structure"
          ],
          limit: [
            type: :pos_integer,
            default: 100,
            doc: "How many nodes to describe, at most 500"
          ]
        ]
      },
      %{
        name: "list_sheets",
        description: """
        Lists the Google Sheets this organisation reads from or writes to in
        flows, with their sync status and any failure reason. A flow that reads
        stale or missing sheet data usually shows up here first.

        Add `include: ["rows"]` to see the synced rows themselves, which is how
        you check whether the data a flow looks up is actually there.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"],
          include: [
            type: {:list, {:in, ["rows"]}},
            default: [],
            doc: ~s(Add "rows" for the synced sheet data)
          ]
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

  @doc "Reads one flow lookup: the list, one flow's structure, its sheets or its webhook calls."
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
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
      described = %{
        id: flow.id,
        name: flow.name,
        keywords: flow.keywords,
        is_active: flow.is_active,
        revision: args[:status],
        nodes: nodes(definition, min(args[:limit], @max_nodes))
      }

      {:ok, args[:include] |> Enum.uniq() |> Enum.reduce(described, &include(&1, &2, flow))}
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

    {:ok, with_rows(sheets, args[:include])}
  end

  @spec with_rows([map()], [String.t()]) :: [map()]
  defp with_rows(sheets, include) do
    if "rows" in include do
      rows = sheet_rows(Enum.map(sheets, & &1.id))
      Enum.map(sheets, &Map.put(&1, :rows, Map.get(rows, &1.id, [])))
    else
      sheets
    end
  end

  @spec sheet_rows([non_neg_integer()]) :: map()
  defp sheet_rows(sheet_ids) do
    SheetData
    |> where([d], d.sheet_id in ^sheet_ids)
    |> order_by([d], asc: d.key)
    |> limit(200)
    |> select([d], {d.sheet_id, %{key: d.key, row_data: d.row_data}})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @spec include(String.t(), map(), Flows.Flow.t()) :: map()
  defp include("contacts", described, flow),
    do: Map.put(described, :contacts, contact_status(flow.id))

  defp include("counts", described, flow), do: Map.put(described, :counts, counts(flow))
  defp include("results", described, flow), do: Map.put(described, :results, results(flow.id))

  defp include("webhooks", described, flow),
    do: Map.put(described, :webhooks, webhook_logs(flow.id))

  @spec counts(Flows.Flow.t()) :: [map()]
  defp counts(flow) do
    flow.uuid
    |> FlowCount.get_flow_count_list()
    |> Enum.map(
      &%{uuid: &1.uuid, type: &1.type, count: &1.count, destination_uuid: &1.destination_uuid}
    )
  end

  @spec results(non_neg_integer()) :: [map()]
  defp results(flow_id) do
    FlowResult
    |> where([r], r.flow_id == ^flow_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(25)
    |> select([r], %{
      contact_id: r.contact_id,
      flow_version: r.flow_version,
      results: r.results,
      inserted_at: r.inserted_at
    })
    |> Repo.all()
  end

  @spec webhook_logs(non_neg_integer()) :: [map()]
  defp webhook_logs(flow_id) do
    WebhookLog
    |> where([l], l.flow_id == ^flow_id)
    |> order_by([l], desc: l.inserted_at)
    |> limit(20)
    |> select([l], %{
      url: l.url,
      method: l.method,
      status_code: l.status_code,
      error: l.error,
      inserted_at: l.inserted_at
    })
    |> Repo.all()
  end

  @spec fetch_flow(non_neg_integer()) :: {:ok, Flows.Flow.t()} | {:error, String.t()}
  defp fetch_flow(flow_id) do
    case Flows.fetch_flow(flow_id) do
      {:ok, flow} -> {:ok, flow}
      {:error, _} -> {:error, "No flow with id #{flow_id} exists in this organisation."}
    end
  end

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

  @spec contact_status(non_neg_integer()) :: map()
  defp contact_status(flow_id) do
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

  @spec nodes(map(), pos_integer()) :: [map()] | map()
  defp nodes(definition, limit) do
    all = Map.get(definition, "nodes", [])

    if length(all) > limit,
      do: %{
        truncated: true,
        showing: Enum.map(Enum.take(all, limit), &node_summary/1),
        of: length(all)
      },
      else: Enum.map(all, &node_summary/1)
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
