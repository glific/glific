defmodule Glific.AskmeBot do
  @moduledoc """
  Glific AskMeBot context module for business logic.
  """

  alias Glific.Dify.ApiClient
  alias Glific.Partners.OrganizationData
  alias Glific.Repo

  @doc """
  Calls the Dify chat-messages API and fetches the answer for AskMe bot.
  Supports conversation history via conversation_id.
  """
  @spec askme(map(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def askme(params, organization_id) do
    Glific.Metrics.increment("AskMeBot Requests")

    query = Map.get(params, :query, "")
    conversation_id = Map.get(params, :conversation_id, "")
    user = user_identifier(organization_id)

    body = %{
      "inputs" => %{"page_url" => "https://glific.org"},
      "query" => query,
      "response_mode" => "blocking",
      "conversation_id" => conversation_id,
      "user" => user
    }

    case ApiClient.chat_messages(body, dify_api_key()) do
      {:ok, response} ->
        answer = Map.get(response, "answer", "")
        resp_conversation_id = Map.get(response, "conversation_id", "")
        # message_id = Map.get(response, "message_id", "")

        {:ok, %{answer: answer, conversation_id: resp_conversation_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec user_identifier(non_neg_integer()) :: String.t()
  defp user_identifier(organization_id), do: "org-#{organization_id}"

  @spec dify_api_key() :: String.t()
  defp dify_api_key, do: Application.get_env(:glific, :dify_api_key, "")
end
