defmodule Glific.Dialogflow.Worker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :gupshup,
    max_attempts: 1,
    priority: 0

  alias Glific.Dialogflow

  @rate_name Application.fetch_env!(:glific, :provider_id)
  @rate_limit Application.fetch_env!(:glific, :provider_limit)

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"method" => method, "path" => path, "body" => body, "message" => message}}) do
    case ExRated.check_rate(@rate_name, 60_000, @rate_limit) do
      {:ok, _} -> Dialogflow.request(method, path, body, message)
        |> IO.inspect()
      _ -> {:error, :rate_limit_exceeded}
    end
    :ok
  end
end
