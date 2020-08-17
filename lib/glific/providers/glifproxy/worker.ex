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
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"message" => message, "payload" => payload}}) do
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactoring because of credo warning
    # We are in a proxy here, we simulate the message has been sent
    # We turn around and actually flip the contact to a proxy number (or vice versa)
    # and send it back to the frontend
    case ExRated.check_rate(@rate_name, 60_000, @rate_limit) do
      {:ok, _} -> proxy_message(message, payload)
      _ -> {:error, :rate_limit_exceeded}
    end

    :ok
  end

  @prefix "000"
  @prefix_len 3
  @trigger "proxy"
  @trigger_len 5

  @doc """
  Proxy the message from a number to a fake proxy contact. Do it one way only
  Don't do the reverse, to avoid infinite loops in automation.
  For a workaroung, the "faker" message is processed in the reverse direction to
  create the contact
  """
  @spec proxy_message(map(), Oban.Job.t()) :: any()
  def proxy_message(message, %{"destination" => destination} = _payload)
    when binary_part(destination, 0, @prefix_len) == @prefix do
    name = String.slice(destination, @prefix_len..-1)

    # we dont have the name with us, so for now, we just
    # use the phone as the name
    {new_destination, name} = {name, name}

    handle_message(new_destination, name, message)
  end

    def proxy_message(%{"body" => body} = message, %{"destination" => destination} = _payload)
    when binary_part(body, 0, @trigger_len) == @trigger do
    {new_destination, name} = {@prefix <> destination, "PROXY " <> destination}

    handle_message(new_destination, name, message)
  end

  def proxy_message(message, _payload), do: {:ok, message}

  @spec handle_message(String.t(), String.t(), map()) :: any()
  defp handle_message(destination, name, message) do
    payload = generate_payload(destination, name, message)

    # lets sleep for 1 seconds before posting, to avoid race
    # conditions with flows et al
    :timer.sleep(1000)

    ApiClient.post("/gupshup", payload)
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
end
