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
  def perform(
        %Oban.Job{args: %{"message" => message, "payload" => payload, "attrs" => attrs}} = job
      ) do
    IO.inspect(message, label: "Message")
    IO.inspect(payload, label: "Payload")
    IO.inspect(attrs, label: "Attributes")
  end
end
