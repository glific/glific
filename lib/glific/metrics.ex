defmodule Glific.Metrics do
  @moduledoc """
  Wrapper for various statistical tables which we can cache and write to in batch. For now, we are
  managing the flow_counts table
  """

  use Supervisor

  @worker Glific.Metrics.Worker
  @worker_tracker Glific.Metrics.WorkerTracker
  @registry Glific.Metrics.Registry
  @supervisor Glific.Metrics.WorkerSupervisor

  require Logger
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
  @spec bump(map()) :: :ok
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
    :ok
  end

  def bump(%{type: :tracker} = args) do
    key = {:tracker, args.organization_id}

    pid =
      case Registry.lookup(@registry, key) do
        [{pid, _}] ->
          pid

        [] ->
          case DynamicSupervisor.start_child(@supervisor, {@worker_tracker, key}) do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
          end
      end

    send(pid, {:bump, args.event, args.count})
    :ok
  end

  @doc """
  Wrapper function for bump that we can call from the main code
  """
  @spec increment(String.t(), non_neg_integer() | nil, non_neg_integer() | nil) :: :ok
  def increment(event, organization_id \\ nil, count \\ 1) do
    organization_id =
      if organization_id == nil,
        do: Glific.Repo.get_organization_id(),
        else: organization_id

    if is_nil(organization_id) do
      Logger.error("Organization id nil for the event #{event}")
    end

    bump(%{
      type: :tracker,
      organization_id: organization_id,
      event: event,
      count: count
    })
  end
end
