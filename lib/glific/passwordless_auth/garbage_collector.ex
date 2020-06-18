defmodule PasswordlessAuth.GarbageCollector do
  @moduledoc """
  Verification codes are stored in the PasswordlessAuth.Store Agent.
  This worker looks for expires verification codes at a set interval
  and removes them from the Agent state.

  The garbage collection interval is configurable with
  `garbage_collector_frequency` (defaults to 30 seconds).
  """
  use GenServer
  alias PasswordlessAuth.Store

  @default_garbage_collector_frequency 30

  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  @doc false
  def init(args) do
    queue_garbage_collection()
    {:ok, args}
  end

  @doc false
  def handle_info(:collect_garbage, args) do
    remove_expired_items()
    queue_garbage_collection()
    {:noreply, args}
  end

  defp queue_garbage_collection do
    frequency =
      Application.get_env(:passwordless_auth, :garbage_collector_frequency) ||
        @default_garbage_collector_frequency

    Process.send_after(self(), :collect_garbage, frequency * 1000)
  end

  defp remove_expired_items do
    current_date_time = NaiveDateTime.utc_now()

    Agent.update(
      Store,
      &(Enum.filter(&1, fn {_, item} ->
          NaiveDateTime.compare(item.expires, current_date_time) == :gt
        end)
        |> Map.new())
    )
  end
end
