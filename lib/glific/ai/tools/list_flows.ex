defmodule Glific.AI.Tools.ListFlows do
  @moduledoc """
  Lists the organisation's flows, so a question naming a flow can be resolved to
  an id before anything else is looked up.
  """

  @behaviour Glific.AI.Tool

  alias Glific.Flows

  @impl Glific.AI.Tool
  def name, do: "list_flows"

  @impl Glific.AI.Tool
  def description do
    """
    Lists the flows in this organisation, with their ids, names and keywords.
    Use this first whenever a question mentions a flow by name, to find its id.
    Optionally filter by a partial name.
    """
  end

  @impl Glific.AI.Tool
  def parameters do
    [
      name: [type: :string, doc: "Only return flows whose name contains this text"],
      limit: [type: :pos_integer, default: 25, doc: "How many flows to return, at most 100"]
    ]
  end

  @impl Glific.AI.Tool
  def run(args) do
    filter = if args[:name], do: %{name: args[:name]}, else: %{}
    opts = %{limit: min(args[:limit], 100), offset: 0, order: :asc}

    flows =
      %{filter: filter, opts: opts}
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
end
