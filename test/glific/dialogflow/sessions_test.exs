defmodule Glific.Dialogflow.SessionsTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  import Mock

  alias Glific.Dialogflow.Sessions
  alias Glific.Dialogflow.SessionWorker
  alias Glific.Fixtures
  alias Glific.Messages
  alias Goth.Token

  @query %{
    "queryResult" => %{
      "action" => "input.unknown",
      "allRequiredParamsPresent" => true,
      "diagnosticInfo" => %{},
      "fulfillmentMessages" => [%{"text" => %{"text" => ["¿Decías?"]}}],
      "fulfillmentText" => "Ups, no he entendido a que te refieres.",
      "intent" => %{
        "displayName" => "Intent.Greeting",
        "name" => "projects/lbot-2131f/agent/intents/5eec5344-8a09-40ba-8f46-1d2ed3f7b0df"
      },
      "intentDetectionConfidence" => 1,
      "languageCode" => "es",
      "parameters" => %{},
      "queryText" => "Hola"
    },
    "responseId" => "ab7b5dca-6f34-4b9b-88cb-d0da5572778a"
  }

  setup do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: Jason.encode!(@query)}
    end)

    :ok
  end

  test "detect_intent/2 will add the message to queue" do
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
      message =
      Fixtures.message_fixture(%{body: "Hola"})
      |> Repo.preload(contact: [:language])

      Sessions.detect_intent(message, "1e8118272e2f69ea6ec98acbb71ab959")
      assert_enqueued(worker: SessionWorker)
      assert %{success: 1, failure: 0} == Oban.drain_queue(queue: :dialogflow)

      message =
        Messages.get_message!(message.id)
        |> Repo.preload([:tags])

      assert hd(message.tags).label == "Greeting"
    end
  end
end
