defmodule Glific.Metrics.Worker do
  @moduledoc """
  Simple worker which caches all the counts for a specific flow and writes them
  out in batches. This allows us to amortize multiple requests into one DB write.

  Module influenced and borrowed from: https://dashbit.co/blog/homemade-analytics-with-ecto-and-elixir
  """
  use GenServer, restart: :temporary

  @registry Glific.Metrics.Registry

  def start_link(key) do
    GenServer.start_link(__MODULE__, key, name: {:via, Registry, {@registry, key}})
  end

  @impl true
  def init({:flow_id, flow_id} = _key) do
    Process.flag(:trap_exit, true)
    {:ok, %{flow_id: flow_id, nodes: %{}}}
  end

  @impl true
  def handle_info(:bump, {path, 0}) do
    schedule_upsert()
    {:noreply, {path, 1}}
  end

  @impl true
  def handle_info(:bump, {path, counter}) do
    {:noreply, {path, counter + 1}}
  end

  defp schedule_upsert() do
    Process.send_after(self(), :upsert, Enum.random(60..300) * 1_000)
  end

  @impl true
  def handle_info(:upsert, {path, counter}) do
    # We first unregister ourselves so we stop receiving new messages.
    Registry.unregister(@registry, path)

    # Schedule to stop in 2 seconds, this will give us time to process
    # any late messages.
    Process.send_after(self(), :stop, 2_000)
    {:noreply, {path, counter}}
  end

  @impl true
  def handle_info(:stop, {path, counter}) do
    # Now we just stop. The terminate callback will write all pending writes.
    {:stop, :shutdown, {path, counter}}
  end

  defp upsert!(path, counter) do
    # store state in DB
  end

  @impl true
  def terminate(_, {_path, 0}), do: :ok
  def terminate(_, {path, counter}), do: upsert!(path, counter)
end
