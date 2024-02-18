defmodule Glific.Providers.Maytapi.WaWorker do
@moduledoc """
  A worker to handle send message in whatsapp group processes
  """

use Oban.Worker,
queue: :wa_group,
max_attempts: 2,
priority: 0

@doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  # @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"message" => message}} = job) do
    IO.inspect(message)
  end



end
