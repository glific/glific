defmodule Glific.Metrics.Worker do
  @moduledoc """
  Simple worker which caches all the counts for a specific flow and writes them
  out in batches. This allows us to amortize multiple requests into one DB write.

  Module influenced and borrowed from: https://dashbit.co/blog/homemade-analytics-with-ecto-and-elixir
  """
  use GenServer, restart: :temporary

  @registry Glific.Metrics.Registry

  alias Glific.{Flows.FlowCount, Repo}

  @doc false
  def start_link(key) do
    GenServer.start_link(__MODULE__, key, name: {:via, Registry, {@registry, key}})
  end

  @doc false
  @impl true
  def init({:flow_id, flow_id} = _key) do
    Process.flag(:trap_exit, true)
    schedule_upsert()
    {:ok, %{flow_id: flow_id, entries: %{}}}
  end

  defp update_entry(entry, count, messages) do
    messages =
      if Map.has_key?(entry, :recent_message),
        do: [entry.recent_message | messages],
        else: messages

    entry
    |> Map.put(:count, count + 1)
    |> Map.put(:recent_messages, messages)
  end

  @spec add_entry(map(), map()) :: map()
  defp add_entry(entry, entries) do
    e = entries[entry.uuid]

    {count, messages} =
      if e != nil,
        do: {e.count, e.recent_messages},
        else: {0, []}

    entries
    |> Map.put(entry.uuid, update_entry(entry, count, messages))
    |> Map.put_new(:organization_id, entry.organization_id)
  end

  @doc false
  defp schedule_upsert do
    # store to database between 1 to 3 minutes
    Process.send_after(self(), :upsert, Enum.random(60..90) * 1_000)
  end

  @doc false
  @impl true
  def handle_info({:bump, entry}, %{flow_id: flow_id, entries: entries}) do
    {:noreply, %{flow_id: flow_id, entries: add_entry(entry, entries)}}
  end

  @impl true
  def handle_info(:upsert, %{flow_id: flow_id} = state) do
    # We first unregister ourselves so we stop receiving new messages.
    Registry.unregister(@registry, {:flow_id, flow_id})

    # Schedule to stop in 2 seconds, this will give us time to process
    # any late messages.
    Process.send_after(self(), :stop, 2_000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:stop, state) do
    # Now we just stop. The terminate callback will write all pending writes.
    {:stop, :shutdown, state}
  end

  @spec upsert!(map()) :: :ok
  defp upsert!(%{entries: entries}) do
    Repo.put_process_state(entries.organization_id)

    # we are only interested in the value of the map, which has map to be inserted
    entries
    |> Map.delete(:organization_id)
    |> Enum.each(&FlowCount.upsert_flow_count(elem(&1, 1)))
  end

  @doc false
  @impl true
  def terminate(_, state), do: upsert!(state)
end
