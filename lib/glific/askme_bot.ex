defmodule Glific.AskmeBot do
  @moduledoc """
  Glific AskMeBot module for all API calls to Dify
  """
  require Logger
  alias Glific.Partners.OrganizationData
  alias Glific.Repo

  @dify_endpoint "https://api.dify.ai/v1"

  @doc """
  Calls the Dify chat-messages API and fetches the answer for AskMe bot.
  Supports conversation history via conversation_id.
  """
  @spec askme(map(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def askme(params, organization_id) do
    Glific.Metrics.increment("AskMeBot Requests")
    api_key = dify_api_key()
    url = @dify_endpoint <> "/chat-messages"

    query = Map.get(params, "query", "")
    conversation_id = Map.get(params, "conversation_id", "")

    body = %{
      "inputs" => %{"page_url" => "https://glific.org"},
      "query" => query,
      "response_mode" => "blocking",
      "conversation_id" => conversation_id,
      "user" => "org-#{organization_id}"
    }

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

    Tesla.client(middleware)
    |> Tesla.post(url, body, opts: [adapter: [recv_timeout: 120_000]])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: response}} ->
        answer = Map.get(response, "answer", "")
        resp_conversation_id = Map.get(response, "conversation_id", "")
        message_id = Map.get(response, "message_id", "")

        attrs = %{
          key: "askme_#{message_id}",
          json: %{
            question: query,
            answer: answer,
            conversation_id: resp_conversation_id,
            message_id: message_id
          },
          organization_id: organization_id
        }

        %OrganizationData{}
        |> OrganizationData.changeset(attrs)
        |> Repo.insert()

        {:ok, %{answer: answer, conversation_id: resp_conversation_id}}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error = "Unexpected Dify response (#{status}): #{inspect(body)}"
        Logger.error(error)
        {:error, error}

      {:error, reason} ->
        error = "HTTP error calling Dify: #{inspect(reason)}"
        Logger.error(error)
        {:error, error}
    end
  end

  @spec dify_api_key() :: String.t()
  defp dify_api_key do
    Application.get_env(:glific, :dify_api_key, "")
  end
end
