defmodule Glific.Metrics do
  use Supervisor

  @worker Glific.Metrics.Worker
  @registry Glific.Metrics.Registry
  @supervisor Glific.Metrics.WorkerSupervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

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
