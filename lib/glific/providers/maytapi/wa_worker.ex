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
  def perform(job) do
    IO.inspect(job, label: "inspecting oban")
    :ok
  end
end
