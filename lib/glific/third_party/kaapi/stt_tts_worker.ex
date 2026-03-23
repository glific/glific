defmodule Glific.ThirdParty.Kaapi.SttTtsWorker do
  @moduledoc """
  Oban worker for Kaapi STT and TTS requests.

  Enforces per-organization rate limiting (via ExRated + snooze) before
  dispatching the async request to the Kaapi unified LLM API. If Kaapi
  returns a failure response, the worker wakes the flow context with a
  Failure message and updates the webhook log. On success, the flow stays
  in the await state and will be woken by the Kaapi callback via
  `flow_resume_controller`.
  """

  use Oban.Worker,
    queue: :gpt_webhook_queue,
    max_attempts: 2

  require Logger

  alias Glific.{
    Flows.FlowContext,
    Messages,
    Partners,
    Repo
  }

  alias Glific.Clients.CommonWebhook
  alias Glific.Flows.Webhook

  # Maximum concurrent Kaapi STT/TTS requests per organization.
  # Window of 60 seconds (60_000 ms).
  @rate_limit_window_ms 60_000
  @rate_limit_max 10

  @doc """
  Standard Oban perform entry point.

  Expected job args:
  - `"webhook_name"` — `"speech_to_text"` or `"text_to_speech"`
  - `"fields"` — map of fields passed to CommonWebhook (already includes org_id, contact_id, etc.)
  - `"webhook_log_id"` — ID of the pre-created WebhookLog entry
  - `"context_id"` — FlowContext ID to wake on failure
  - `"organization_id"` — org ID (integer)
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{
        args: %{
          "webhook_name" => webhook_name,
          "fields" => fields,
          "webhook_log_id" => webhook_log_id,
          "context_id" => context_id,
          "organization_id" => organization_id
        }
      }) do
    Repo.put_process_state(organization_id)
    organization = Partners.organization(organization_id)

    rate_limit_key = "kaapi_stt_tts:#{organization.shortcode}"

    case ExRated.check_rate(rate_limit_key, @rate_limit_window_ms, @rate_limit_max) do
      {:ok, _count} ->
        do_kaapi_call(webhook_name, fields, webhook_log_id, context_id, organization_id)

      {:error, _limit} ->
        Logger.info(
          "Kaapi STT/TTS rate limit reached for org=#{organization.shortcode}, snoozing job"
        )

        {:snooze, 5}
    end
  end

  @spec do_kaapi_call(String.t(), map(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  defp do_kaapi_call(webhook_name, fields, webhook_log_id, context_id, organization_id) do
    response = CommonWebhook.webhook(webhook_name, fields, [])

    case response do
      %{success: true} ->
        # Kaapi acknowledged. The flow stays in await state; Kaapi will POST the
        # result to the flow_resume callback URL which will wake the flow.
        :ok

      %{success: false} = failure ->
        reason = Map.get(failure, :reason, "Kaapi request failed")
        error_type = Map.get(failure, :error_type, "service_unavailable")

        Logger.warning(
          "Kaapi #{webhook_name} failed for org=#{organization_id}: error_type=#{error_type}, reason=#{reason}"
        )

        Webhook.update_log(webhook_log_id, %{
          success: false,
          error_type: error_type,
          reason: reason
        })

        wake_flow_with_failure(context_id, organization_id)

      _ ->
        Webhook.update_log(webhook_log_id, "Unexpected response from Kaapi")
        wake_flow_with_failure(context_id, organization_id)
    end
  end

  @spec wake_flow_with_failure(non_neg_integer(), non_neg_integer()) :: :ok | {:error, String.t()}
  defp wake_flow_with_failure(context_id, organization_id) do
    context =
      Repo.get!(FlowContext, context_id)
      |> Repo.preload(:flow)

    failure_message = Messages.create_temp_message(organization_id, "Failure")

    case FlowContext.wakeup_one(context, failure_message) do
      {:ok, _context, _messages} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to wake flow context #{context_id} for org=#{organization_id}: #{inspect(reason)}"
        )

        {:error, "Failed to wake flow context #{context_id}: #{inspect(reason)}"}
    end
  end

  @doc """
  Enqueue a Kaapi STT or TTS job. Called from `Webhook.execute_kaapi_stt/tts`.
  """
  @spec enqueue(String.t(), map(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(webhook_name, fields, webhook_log_id, context_id, organization_id) do
    %{
      webhook_name: webhook_name,
      fields: fields,
      webhook_log_id: webhook_log_id,
      context_id: context_id,
      organization_id: organization_id
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
