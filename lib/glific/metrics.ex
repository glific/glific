defmodule Glific.Metrics do
  @moduledoc """
  Wrapper for various statistical tables which we can cache and write to in batch. For now, we are
  managing the flow_counts table
  """

  use Supervisor

  @worker Glific.Metrics.Worker
  @registry Glific.Metrics.Registry
  @supervisor Glific.Metrics.WorkerSupervisor

  @doc false
  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Bump the count for a specific node/exit within a flow
  """
  @spec bump(map()) :: any
  def bump(%{flow_id: flow_id} = args) when is_integer(flow_id) do
    key = {:flow_id, flow_id}

    pid =
      case Registry.lookup(@registry, key) do
        [{pid, _}] ->
          pid

        [] ->
          case DynamicSupervisor.start_child(@supervisor, {@worker, key}) do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
          end
      end

    send(pid, {:bump, args})
  end
end
