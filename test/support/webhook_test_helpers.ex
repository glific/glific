defmodule Glific.WebhookTestHelpers do
  @moduledoc false

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Flows.Flow,
    Flows.FlowContext,
    Flows.WebhookLog,
    Messages.Message,
    Repo
  }

  @await_attempts 50
  @await_interval_ms 100

  @doc "Poll for a message matching expected_body sent to contact_id."
  @spec await_flow_message(non_neg_integer(), String.t()) :: Message.t()
  def await_flow_message(contact_id, expected_body) do
    await_flow_message(contact_id, expected_body, @await_attempts)
  end

  defp await_flow_message(_contact_id, expected_body, 0) do
    raise "Timed out waiting for message #{inspect(expected_body)}"
  end

  defp await_flow_message(contact_id, expected_body, attempts) do
    # Match the expected message anywhere in the contact's messages, not just the
    # most recent one — a resumed flow may emit several messages, and messages
    # sharing an inserted_at tick order non-deterministically.
    Glific.Messages.list_messages(%{filter: %{contact_id: contact_id}})
    |> Enum.find(&(&1.body == expected_body))
    |> case do
      %Message{} = msg ->
        msg

      nil ->
        Process.sleep(@await_interval_ms)
        await_flow_message(contact_id, expected_body, attempts - 1)
    end
  end

  @doc """
  Build a FlowContext parked in await state at the first node of the call_and_wait flow.
  Returns {contact, webhook_log, flow}.
  """
  @spec build_await_context(non_neg_integer()) :: {Contact.t(), WebhookLog.t(), Flow.t()}
  def build_await_context(organization_id) do
    contact = Fixtures.contact_fixture(%{organization_id: organization_id})
    webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    {:ok, _context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        uuid_map: %{},
        organization_id: organization_id,
        wakeup_at: DateTime.add(DateTime.utc_now(), 60),
        is_await_result: true,
        node_uuid: node.uuid
      })

    {contact, webhook_log, flow}
  end

  @doc """
  Build a FlowContext linked to the call_and_wait flow (not in await state).
  Returns {context, flow_attrs}.
  """
  @spec build_flow_context(non_neg_integer(), non_neg_integer()) :: {FlowContext.t(), map()}
  def build_flow_context(organization_id, contact_id) do
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    flow_attrs = %{
      flow_id: flow.id,
      flow_uuid: flow.uuid,
      contact_id: contact_id,
      organization_id: organization_id,
      node_uuid: node.uuid,
      is_await_result: true,
      wakeup_at: DateTime.add(DateTime.utc_now(), 60)
    }

    {:ok, context} = FlowContext.create_flow_context(flow_attrs)
    {Repo.preload(context, [:contact, :flow]), flow_attrs}
  end

  @doc """
  Callback params in the unified-API format (metadata + data.response.output).
  Used by speech_to_text, text_to_speech, voice_filesearch_gpt tests.
  Pass extra_metadata to merge additional metadata fields (e.g., voice_post_process).
  """
  @spec build_unified_callback_params(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          boolean(),
          String.t(),
          map()
        ) :: map()
  def build_unified_callback_params(
        organization_id,
        flow_id,
        contact_id,
        webhook_log_id,
        success,
        message,
        extra_metadata \\ %{}
      ) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    signature_payload = %{
      "organization_id" => organization_id,
      "flow_id" => flow_id,
      "contact_id" => contact_id,
      "timestamp" => timestamp
    }

    signature =
      Glific.signature(
        organization_id,
        Jason.encode!(signature_payload),
        timestamp
      )

    metadata =
      Map.merge(
        %{
          "organization_id" => organization_id,
          "flow_id" => flow_id,
          "contact_id" => contact_id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log_id,
          "result_name" => "filesearch"
        },
        extra_metadata
      )

    %{
      "data" => %{
        "response" => %{
          "output" => %{
            "type" => "text",
            "content" => %{"value" => message}
          }
        }
      },
      "metadata" => metadata,
      "success" => success
    }
  end
end
