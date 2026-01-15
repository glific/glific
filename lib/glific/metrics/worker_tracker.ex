defmodule Glific.Metrics.WorkerTracker do
  @moduledoc """
  Simple worker which caches all the counts for a specific organization and writes them
  out in batches. This allows us to amortize multiple requests into one DB write.

  Module influenced and borrowed from: https://dashbit.co/blog/homemade-analytics-with-ecto-and-elixir
  """
  use GenServer, restart: :temporary

  @registry Glific.Metrics.Registry

  alias Glific.{Repo, Trackers}

  @doc false
  def start_link(key) do
    GenServer.start_link(__MODULE__, key, name: {:via, Registry, {@registry, key}})
  end

  @doc false
  @impl true
  def init({:tracker, organization_id} = _key) do
    Process.flag(:trap_exit, true)
    schedule_upsert()
    {:ok, %{organization_id: organization_id, counts: %{}}}
  end

  defp bump(counts, event, count), do: Map.update(counts, event, count, fn v -> v + count end)

  @doc false
  defp schedule_upsert do
    # store to database between 5 to 15 minutes (for prod)
    # and 5 to 15 seconds for other
    time_factor =
      if Application.get_env(:glific, :environment) == :prod,
        do: 1_000,
        else: 1_0

    Process.send_after(self(), :upsert, Enum.random(300..900) * time_factor)
  end

  @doc false
  @impl true
  def handle_info({:bump, event, count}, %{organization_id: organization_id, counts: counts}) do
    {:noreply, %{organization_id: organization_id, counts: bump(counts, event, count)}}
  end

  @impl true
  def handle_info(:upsert, %{organization_id: organization_id} = state) do
    # We first unregister ourselves so we stop receiving new messages.
    Registry.unregister(@registry, {:tracker, organization_id})

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

  @spec upsert!(map()) :: any
  defp upsert!(%{organization_id: organization_id, counts: counts}) do
    Repo.put_process_state(organization_id)

    # we are only interested in the value of the map, which has map to be inserted
    Trackers.upsert_tracker(counts, organization_id)
  end

  @doc false
  @impl true
  def terminate(_, state), do: upsert!(state)
end
