defmodule Glific.Providers.Glifproxy.Worker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :glifproxy,
    max_attempts: 2,
    priority: 0

  alias Glific.Communications
  alias Glific.Providers.Gupshup.ApiClient

  @rate_name Application.fetch_env!(:glific, :provider_id)
  @rate_limit Application.fetch_env!(:glific, :provider_limit)

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(map(), Oban.Job.t()) :: {:ok, :queue_started}
  def perform(%{"message" => message, "payload" => payload}, _job) do
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactoring because of credo warning
    # We are in a proxy here, we simulate the message has been sent
    # We turn around and actually flip the contact to a proxy number (or vice versa)
    # and send it back to the frontend
    case ExRated.check_rate(@rate_name, 60_000, @rate_limit) do
      {:ok, _} -> proxy_message(message, payload)
      _ -> {:error, :rate_limit_exceeded}
    end

    {:ok, :queue_started}
  end

  @doc """
  We transform a payload that has been set for sending to a payload that has been
  tailored for receiving. We need to generate a few random ids for various messages ids
  """
  @prefix "000"
  @prefix_len 3

  @spec proxy_message(map(), Oban.Job.t()) :: any()
  def proxy_message(message, payload) do
    destination = payload["destination"]

    {new_destination, name} =
      if String.slice(destination, 0, @prefix_len) == @prefix do
        # we dont have the name with us, so for now, we just
        # use the phone as the name
        name = String.slice(destination, @prefix_len..-1)
        {name, name}
      else
        {@prefix <> destination, "PROXY " <> destination}
      end

    new_payload = generate_payload(new_destination, name, message)

    ApiClient.post("/gupshup", new_payload)
    |> handle_response(message)
  end

  @spec generate_payload(String.t(), String.t(), map()) :: map()
  defp generate_payload(destination, name, message) do
    %{
      app: "Glific Proxy App",
      timestamp: DateTime.to_unix(DateTime.utc_now()),
      version: 2,
      type: "message",
      payload: %{
        id: Faker.String.base64(30),
        source: destination,
        type: "text",
        payload: %{
          text: message["body"]
        },
        sender: %{
          phone: destination,
          name: name
        }
      }
    }
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
    Communications.Message.handle_success_response(response, message)
  end

  @doc false
  @spec error_response(Tesla.Env.t(), Glific.Messages.Message.t()) :: {:error, String.t()}
  defp error_response(response, message) do
    Communications.Message.handle_error_response(response, message)
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
