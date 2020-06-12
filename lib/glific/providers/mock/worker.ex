defmodule Glific.Providers.Mock.Worker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :mock,
    max_attempts: 3,
    priority: 0

  alias Glific.Communications.Message, as: Communications
  alias Glific.Providers.Mock.ApiClient

  @rate_name Application.fetch_env!(:glific, :provider_id)
  @rate_limit Application.fetch_env!(:glific, :provider_limit)

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(map(), Oban.Job.t()) :: {:ok, :queue_started}
  def perform(%{"message" => message, "payload" => payload}, _job) do
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactring because of credo warning
    case ExRated.check_rate(@rate_name, 60_000, @rate_limit) do
      {:ok, _} -> ApiClient.mock("/msg", payload)
              |> handle_response(message)
      _ -> {:error, :rate_limit_exceeded}
    end

    {:ok, :queue_started}
  end

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, Glific.Messages.Message.t()) ::
          {:ok, Glific.Messages.Message.t()} | {:error, String.t()}
  defp handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: 200} -> success_response(response, message)
      _ -> error_response(response, message)
    end
  end

  @doc false
  @spec success_response(%Tesla.Env{:status => 200}, Glific.Messages.Message.t()) ::
          {:ok, Glific.Messages.Message.t()}
  defp success_response(response, message) do
    Communications.handle_success_response(response, message)
  end

  @doc false
  @spec error_response(Tesla.Env.t(), Glific.Messages.Message.t()) :: {:error, String.t()}
  defp error_response(response, message) do
    Communications.handle_error_response(response, message)
  end

  @doc """
    We backoff exponentially but always delay by at least 60 seconds
    this needs more work and tweaking
  """
  @impl Oban.Worker
  @spec backoff(integer()) :: pos_integer()
  def backoff(attempt) do
    trunc(:math.pow(attempt, 4) + 60 + :rand.uniform(30) * attempt)
  end
end
