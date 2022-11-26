defmodule Glific.Providers.Airtel.Worker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :airtel,
    max_attempts: 2,
    priority: 0

  alias Glific.{
    Providers.Airtel.ApiClient
  }

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"message" => message, "payload" => payload}} = _job) do
    # need to add validations and error cases
    ApiClient.send_message(message["organization_id"], payload)
    :ok
  end
end
