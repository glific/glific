defmodule Glific.ThirdParty.Kaapi.SttTtsWorker do
  @moduledoc """
  Deprecated compatibility worker.

  STT/TTS (and all Kaapi async webhooks) now run through the generic
  `Glific.Flows.Webhook` Oban worker. This module no longer gets enqueued by any
  current code — it exists only to drain old-format jobs that may still be sitting in
  the `:gpt_webhook_queue` across a deploy, so they route through the new dispatch path
  instead of failing with an `UndefinedFunctionError`.

  Safe to delete once no old-format jobs remain in the queue (one release later).
  """

  use Oban.Worker,
    queue: :gpt_webhook_queue,
    max_attempts: 2

  require Logger

  alias Glific.Flows.FlowContext
  alias Glific.Flows.Webhook
  alias Glific.Flows.Webhooks.Dispatcher
  alias Glific.Messages
  alias Glific.Repo

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()}
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

    case Dispatcher.dispatch(webhook_name, fields, []) do
      # Kaapi accepted the request — leave the flow parked; the callback resumes it.
      %{success: true} ->
        :ok

      # Dispatch failed — record it and wake the flow on the Failure branch.
      failure ->
        Webhook.update_log(webhook_log_id, failure)
        wake_with_failure(context_id, organization_id)
    end
  end

  @spec wake_with_failure(non_neg_integer(), non_neg_integer()) :: :ok
  defp wake_with_failure(context_id, organization_id) do
    case Repo.get(FlowContext, context_id) do
      nil ->
        :ok

      context ->
        message = Messages.create_temp_message(organization_id, "Failure")
        context |> Repo.preload(:flow) |> FlowContext.wakeup_one(message)
        :ok
    end
  end
end
