defmodule Glific.Flowex.SessionsTest do
  use ExUnit.Case

  import Mock

  alias Glific.Flowex.Sessions
  alias Goth.Token

  @query %{
    "queryResult" => %{
      "action" => "input.unknown",
      "allRequiredParamsPresent" => true,
      "diagnosticInfo" => %{},
      "fulfillmentMessages" => [%{"text" => %{"text" => ["¿Decías?"]}}],
      "fulfillmentText" => "Ups, no he entendido a que te refieres.",
      "intent" => %{
        "displayName" => "Default Fallback Intent",
        "name" => "projects/lbot-2131f/agent/intents/5eec5344-8a09-40ba-8f46-1d2ed3f7b0df"
      },
      "intentDetectionConfidence" => 1,
      "languageCode" => "es",
      "parameters" => %{},
      "queryText" => "Hola"
    },
    "responseId" => "ab7b5dca-6f34-4b9b-88cb-d0da5572778a"
  }

  test "detect_intent/2 processes a natural language query" do
    with_mocks([
      {
        Token,
        [:passthrough],
        [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
      },
      {
        HTTPoison,
        [:passthrough],
        [
          request: fn _method, _url, _params, _headers ->
            body = Poison.encode!(@query)
            {:ok, %HTTPoison.Response{status_code: 200, body: body}}
          end
        ]
      }
    ]) do
      assert Sessions.detect_intent("lbot-170198", "Hola", "1e8118272e2f69ea6ec98acbb71ab959") ==
               {:ok, @query}
    end
  end
end
