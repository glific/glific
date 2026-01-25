defmodule Glific.Dialogflow.SessionsTest do
  use Glific.DataCase, async: false
  use Oban.Testing, repo: Glific.Repo
  import Mock

  alias Glific.{
    Dialogflow.Sessions,
    Dialogflow.SessionWorker,
    Fixtures,
    Flows.FlowContext,
    Partners
  }

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

  @default_goth_json """
  {
  "project_id": "DEFAULT PROJECT ID",
  "private_key_id": "DEFAULT API KEY",
  "client_email": "DEFAULT CLIENT EMAIL",
  "private_key": "DEFAULT PRIVATE KEY"
  }
  """

  setup_with_mocks([
    {
      Goth.Token,
      [:passthrough],
      [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
    }
  ]) do
    %{token: "0xFAKETOKEN_Q="}
  end

  setup do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: Jason.encode!(@query)}
    end)

    :ok
  end

  ## We will come back on this one after completing the create credentials functionality
  test "detect_intent/2 will add the message to queue" do
    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
      end
    ) do
      message =
        Fixtures.message_fixture(%{body: "Hola", session_uuid: Ecto.UUID.generate()})
        |> Repo.preload(contact: [:language])

      valid_attrs = %{
        secrets: %{"service_account" => @default_goth_json},
        is_active: true,
        shortcode: "dialogflow",
        organization_id: message.organization_id
      }

      {:ok, _credential} = Partners.create_credential(valid_attrs)

      [flow | _] = Glific.Flows.list_flows(%{organization_id: message.organization_id})

      {:ok, context} =
        FlowContext.create_flow_context(%{
          contact_id: message.contact_id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: message.organization_id
        })

      Sessions.detect_intent(message, context.id, "test_result_name")

      assert_enqueued(worker: SessionWorker, prefix: "global")

      assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :dialogflow)
    end
  end
end
