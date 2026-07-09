defmodule Glific.Flows.Webhooks.ParseViaChatGpt do
  @moduledoc """
  Parse a message via OpenAI ChatGPT (`parse_via_chat_gpt` flow-webhook node).

  Migrated from `Glific.Clients.CommonWebhook.webhook("parse_via_chat_gpt", ...)` onto the
  central `Glific.Flows.Webhooks` framework; behaviour is preserved one-for-one. Failure
  reporting and latency telemetry are added by `Glific.Flows.Webhooks.Dispatcher`, not here.

  `call/2` returns `%{success: true, parsed_msg: ...}` on success, or a typed
  `{:error, ErrorType.t(), message}` on failure (which the dispatcher turns into a bare string
  routing the flow to its "Failure" category). An empty question is `:empty_input` (config);
  an OpenAI error the node can't judge is `:unknown` (→ system).
  """

  use Glific.Flows.Webhooks.Sync, name: "parse_via_chat_gpt"

  alias Glific.Flows.Webhooks.ErrorType
  alias Glific.OpenAI.ChatGPT

  @impl true
  @spec call(map(), Glific.Flows.Webhooks.Behaviour.ctx()) ::
          map() | {:error, ErrorType.t(), String.t()}
  def call(fields, _ctx) do
    with {:ok, fields} <- parse_chatgpt_fields(fields),
         {:ok, fields} <- ChatGPT.parse_response_format(fields),
         {:ok, text} <- Glific.get_open_ai_key() |> ChatGPT.parse(fields) do
      %{
        success: true,
        parsed_msg: ChatGPT.parse_gpt_response(text)
      }
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
         # ID of the model to use.
         "model" => Map.get(fields, "model", "gpt-4o"),
         # The sampling temperature, between 0 and 1.
         # Higher values like 0.8 will make the output more random,
         # while lower values like 0.2 will make it more focused and deterministic.
         "temperature" => Map.get(fields, "temperature", 0),
         "response_format" => Map.get(fields, "response_format", nil)
       }}
    end
  end
end
