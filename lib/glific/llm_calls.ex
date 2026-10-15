defmodule Glific.LlmCalls do
  @moduledoc """
  Records the Kaapi LLM calls made from flow nodes.
  """

  alias Glific.{
    Flows.WebhookLog,
    LlmCalls.LlmCall,
    Repo
  }

  @doc "Create an LLM call record"
  @spec create_llm_call(map()) :: {:ok, LlmCall.t()} | {:error, Ecto.Changeset.t()}
  def create_llm_call(attrs) do
    %LlmCall{}
    |> LlmCall.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Record an LLM call from the raw Kaapi callback `result` and its parsed `response`."
  @spec create_llm_call_from_callback(non_neg_integer(), map(), map()) ::
          {:ok, LlmCall.t()} | {:error, Ecto.Changeset.t()}
  def create_llm_call_from_callback(organization_id, result, response) do
    metadata = result["metadata"] || %{}
    llm_response = get_in(result, ["data", "response"]) || %{}
    input_guardrail = metadata["input_guardrail"]
    output_guardrail = metadata["output_guardrail"]
    output = text_output(llm_response["output"])
    question = input_guardrail["input_from_user"] || question(response["webhook_log_id"])

    create_llm_call(%{
      organization_id: organization_id,
      flow_id: response["flow_id"],
      contact_id: response["contact_id"],
      success: result["success"],
      error: result["error"],
      provider_response_id: llm_response["provider_response_id"],
      conversation_id: llm_response["conversation_id"],
      provider: llm_response["provider"],
      model: llm_response["model"],
      input_from_user: question,
      input_to_llm: input_guardrail["input_to_llm"] || question,
      output_from_llm: output_guardrail["output_from_llm"] || output,
      output_to_user: output_guardrail["output_to_user"] || output,
      input_guardrail: input_guardrail["validators"],
      output_guardrail: output_guardrail["validators"],
      tokens: get_in(result, ["data", "usage"])
    })
  end

  # Without an input guardrail the callback doesn't echo the input, so read the question the
  # flow node sent from its webhook log.
  @spec question(non_neg_integer() | nil) :: String.t() | nil
  defp question(nil), do: nil

  defp question(webhook_log_id) do
    case Repo.get(WebhookLog, webhook_log_id) do
      %WebhookLog{request_json: %{"question" => question}} -> question
      _ -> nil
    end
  end

  @spec text_output(map() | nil) :: String.t() | nil
  defp text_output(%{"type" => "text", "content" => %{"value" => value}}), do: value
  defp text_output(_output), do: nil
end
