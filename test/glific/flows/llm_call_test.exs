defmodule Glific.Flows.LlmCallTest do
  use Glific.DataCase

  import Glific.WebhookTestHelpers

  alias Glific.{
    Fixtures,
    Flows.LlmCall,
    Flows.Webhook,
    Repo
  }

  @input_guardrail %{
    "input_from_user" => "call me kutta at 8979220110 from Ram village",
    "input_to_llm" => "call me [REDACTED_SLUR] at <phone_number> from <location>",
    "validators" => [
      %{
        "name" => "LexicalSlur",
        "outcome" => "FAIL",
        "error" => "Mentioned toxic words: kutta"
      }
    ]
  }

  @output_guardrail %{
    "output_from_llm" => "Call me at 8979220110",
    "output_to_user" => "Call me at <PHONE_NUMBER>",
    "validators" => [%{"name" => "PIIRemover", "outcome" => "FAIL"}]
  }

  defp callback(attrs) do
    Map.merge(
      %{
        "success" => true,
        "error" => nil,
        "data" => %{
          "response" => %{
            "provider_response_id" => "resp_123",
            "conversation_id" => "conv_123",
            "provider" => "openai-native",
            "model" => "gpt-5.4-mini",
            "output" => %{"type" => "text", "content" => %{"value" => "Hello!"}}
          },
          "usage" => %{
            "input_tokens" => 280,
            "output_tokens" => 217,
            "total_tokens" => 497,
            "reasoning_tokens" => nil
          }
        },
        "metadata" => %{"warnings" => []}
      },
      attrs
    )
  end

  test "record_callback/3 stores the guardrail input and output",
       %{organization_id: organization_id} do
    result =
      callback(%{
        "metadata" => %{
          "input_guardrail" => @input_guardrail,
          "output_guardrail" => @output_guardrail
        }
      })

    assert {:ok, llm_call} = LlmCall.record_callback(organization_id, result, %{})

    assert llm_call.success
    assert llm_call.input_from_user == @input_guardrail["input_from_user"]
    assert llm_call.input_to_llm == @input_guardrail["input_to_llm"]
    assert llm_call.input_guardrail == @input_guardrail
    assert llm_call.output_from_llm == @output_guardrail["output_from_llm"]
    assert llm_call.output_to_user == @output_guardrail["output_to_user"]
    assert llm_call.output_guardrail == @output_guardrail
    assert llm_call.provider_response_id == "resp_123"
    assert llm_call.model == "gpt-5.4-mini"
    assert llm_call.total_tokens == 497
  end

  test "record_callback/3 falls back to the question and LLM output without guardrails",
       %{organization_id: organization_id} do
    webhook_log =
      Fixtures.webhook_log_fixture(%{
        organization_id: organization_id,
        request_json: %{"question" => "What is Glific?"}
      })

    assert {:ok, llm_call} =
             LlmCall.record_callback(organization_id, callback(%{}), %{
               "webhook_log_id" => webhook_log.id
             })

    assert llm_call.input_from_user == "What is Glific?"
    assert llm_call.input_to_llm == "What is Glific?"
    assert llm_call.input_guardrail == nil
    assert llm_call.output_from_llm == "Hello!"
    assert llm_call.output_to_user == "Hello!"
  end

  test "record_callback/3 records a failed call", %{organization_id: organization_id} do
    result = %{"success" => false, "data" => nil, "error" => "Kaapi failed", "metadata" => %{}}

    assert {:ok, llm_call} = LlmCall.record_callback(organization_id, result, %{})

    refute llm_call.success
    assert llm_call.error == "Kaapi failed"
    assert llm_call.output_to_user == nil
  end

  test "Webhook.resume/3 records only LLM callbacks", %{organization_id: organization_id} do
    {contact, webhook_log, flow} = build_await_context(organization_id)

    response = %{
      "contact_id" => contact.id,
      "flow_id" => flow.id,
      "webhook_log_id" => webhook_log.id,
      "call_type" => "llm"
    }

    Webhook.resume(organization_id, callback(%{}), response)

    assert [%LlmCall{contact_id: contact_id, flow_id: flow_id}] = Repo.all(LlmCall)
    assert contact_id == contact.id
    assert flow_id == flow.id

    Webhook.resume(organization_id, callback(%{}), Map.put(response, "call_type", "stt"))
    assert Repo.aggregate(LlmCall, :count) == 1
  end
end
