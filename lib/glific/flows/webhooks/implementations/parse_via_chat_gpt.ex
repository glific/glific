defmodule Glific.Flows.Webhooks.ParseViaChatGpt do
  @moduledoc """
  Parse a message via OpenAI ChatGPT (`parse_via_chat_gpt` node).
  """

  use Glific.Flows.Webhooks.Sync, name: "parse_via_chat_gpt"

  alias Glific.Flows.Webhooks.ErrorType
  alias Glific.OpenAI.ChatGPT

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          {:ok, map()} | {:error, ErrorType.t(), String.t()}
  def call(fields, _ctx) do
    with {:ok, fields} <- parse_chatgpt_fields(fields),
         {:ok, fields} <- ChatGPT.parse_response_format(fields),
         {:ok, text} <- Glific.get_open_ai_key() |> ChatGPT.parse(fields) do
      {:ok,
       %{
         success: true,
         parsed_msg: ChatGPT.parse_gpt_response(text)
       }}
    else
      {:error, error_type, message} -> {:error, error_type, message}
      {:error, message} -> {:error, :unknown, message}
    end
  end

  @spec parse_chatgpt_fields(map()) :: {:ok, map()} | {:error, ErrorType.t(), String.t()}
  defp parse_chatgpt_fields(fields) do
    if fields["question_text"] in [nil, ""] do
      {:error, :empty_input, "question_text is empty"}
    else
      {:ok,
       %{
         "question_text" => Map.get(fields, "question_text"),
         "prompt" => Map.get(fields, "prompt", nil),
         "model" => Map.get(fields, "model", "gpt-4o"),
         "temperature" => Map.get(fields, "temperature", 0),
         "response_format" => Map.get(fields, "response_format", nil)
       }}
    end
  end
end
