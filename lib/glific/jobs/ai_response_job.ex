defmodule Glific.Jobs.AiResponseJob do
  @moduledoc """
  This job checks if an AI platform response has been received within a specified time period.
  If not, it marks the flow context as failed and wakes up the flow to continue processing.

  This is used as an alternative to blocking Process.sleep calls when waiting for AI platform responses.
  """
  use Oban.Worker,
    queue: :ai_response,
    max_attempts: 1,
    priority: 0,
    unique: [
      period: 60,
      fields: [:args],
      keys: [:context_id],
      states: [:available, :scheduled, :executing]
    ]

  require Logger
  alias Glific.{Messages, Repo}
  alias Glific.Flows.{FlowContext, WebhookLog}

  @doc """
  Schedule a job to check for an AI platform response after a specified timeout.
  Creates a webhook log to track this operation.
  """
  @spec schedule_job(FlowContext.t(), non_neg_integer(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, any()}
  def schedule_job(context, timeout_seconds \\ 60, url \\ "ai_response") do
    IO.inspect("going in AI")
    # Create a webhook log entry to track this operation
    {:ok, webhook_log} =
      %{
        url: url,
        method: "AI_RESPONSE_CHECK",
        request_headers: %{},
        request_json: %{
          context_id: context.id,
          timeout_seconds: timeout_seconds,
          scheduled_at: DateTime.utc_now() |> DateTime.to_string()
        },
        organization_id: context.organization_id,
        flow_id: context.flow_id,
        contact_id: context.contact_id,
        wa_group_id: context.wa_group_id
      }
      |> WebhookLog.create_webhook_log()

    %{
      context_id: context.id,
      organization_id: context.organization_id,
      webhook_log_id: webhook_log.id
    }
    |> __MODULE__.new(schedule_in: timeout_seconds)
    |> Oban.insert()
  end

  @doc """
  Implementation of worker perform method.

  Checks if the flow context is still waiting for a result (is_await_result is true).
  If it is, it means we didn't receive a response from the AI platform within the timeout period,
  so we mark it as failed and wake up the flow to continue.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "context_id" => context_id,
          "organization_id" => organization_id,
          "webhook_log_id" => webhook_log_id
        }
      }) do
    Repo.put_process_state(organization_id)

    context = FlowContext |> Repo.get(context_id)
    webhook_log = WebhookLog |> Repo.get(webhook_log_id)

    case context do
      %FlowContext{is_await_result: false} ->
        IO.inspect("going in false")
        # Response was already received and processed, nothing to do
        Logger.info("AI Response Job: Context #{context_id} already processed")

        update_webhook_log(webhook_log, %{
          status_code: 200,
          response_json: %{
            status: "success",
            message: "Response was already received and processed"
          }
        })

        :ok

      %FlowContext{is_await_result: true} ->
        IO.inspect("goign in true")
        # No response received within timeout, mark as failed and wake up flow
        Logger.warning(
          "AI Response Job: No response received for context #{context_id}, timing out"
        )

        # Create a failure message
        message = Messages.create_temp_message(organization_id, "AI Response Timeout")

        # Update context to indicate we're no longer waiting
        timeout_result = %{
          inserted_at: DateTime.utc_now(),
          success: false,
          reason: "Timeout waiting for AI platform response"
        }

        {:ok, updated_context} =
          FlowContext.update_flow_context(
            context,
            %{
              is_await_result: false,
              results: Map.put(context.results || %{}, "ai_response_timeout", timeout_result)
            }
          )

        # Update the webhook log with the timeout information
        update_webhook_log(webhook_log, %{
          # Request Timeout
          status_code: 408,
          response_json: timeout_result,
          error: "Timeout waiting for AI platform response"
        })

        # Wake up the flow to continue processing
        FlowContext.wakeup_one(updated_context, message)
        :ok
    end
  end

  @spec update_webhook_log(WebhookLog.t() | nil, map()) ::
          {:ok, WebhookLog.t()} | {:error, any()} | nil
  defp update_webhook_log(nil, _attrs), do: nil

  defp update_webhook_log(webhook_log, attrs) do
    WebhookLog.update_webhook_log(webhook_log, attrs)
  end
end
