defmodule Glific.AI.Sweeper do
  @moduledoc """
  Five-minute reconciliation for `ai_conversations` whose Oban job row is gone.

  `Oban.Pro.Plugins.DynamicPruner` deletes a completed job row five minutes after it finishes
  (`config/config.exs`), and `ai_conversations.active_status`/`gate_expires_at` is the only
  durable place a run's status lives — see `Glific.AI.StepWorker`'s moduledoc. A pruned job
  otherwise leaves a permanently spinning UI with nothing left to reconcile it. `run/1` is called
  once per active organization from `Glific.Jobs.MinuteWorker`'s `"five_minute_tasks"` branch,
  and reconciles two ways a conversation can be stuck without a corresponding live job:

    * a confirmation gate that lapsed — `active_status: :awaiting_confirmation` past
      `gate_expires_at`
    * a run stuck `active_status: :running` with no message written in the last 10 minutes —
      orphaned by a crash `Oban.Pro.Plugins.DynamicLifeline` never got to, or a bug that stopped
      enqueueing the next step

  Every conversation this sweeps is published as a terminal event, the same way
  `Glific.AI.StepWorker` publishes when it drives a run to `:done`/`:failed` itself — the UI
  reconciles identically whether a run ended cleanly or was swept up here.
  """

  import Ecto.Query

  alias Glific.AI.Conversation
  alias Glific.AI.Publisher
  alias Glific.Repo

  @stall_minutes 10

  @doc "Sweeps `organization_id`'s stuck conversations."
  @spec run(non_neg_integer()) :: :ok
  def run(organization_id) do
    expire_gates(organization_id)
    fail_stalled_runs(organization_id)
    :ok
  end

  @spec expire_gates(non_neg_integer()) :: :ok
  defp expire_gates(organization_id) do
    now = DateTime.utc_now()

    Conversation
    |> where([c], c.organization_id == ^organization_id)
    |> where([c], c.active_status == :awaiting_confirmation and c.gate_expires_at < ^now)
    |> Repo.all()
    |> Enum.each(&terminate(&1, "gate_expired", "The confirmation window expired."))
  end

  @spec fail_stalled_runs(non_neg_integer()) :: :ok
  defp fail_stalled_runs(organization_id) do
    stalled_before = DateTime.add(DateTime.utc_now(), -@stall_minutes * 60, :second)

    Conversation
    |> where([c], c.organization_id == ^organization_id)
    |> where([c], c.active_status == :running)
    |> where([c], coalesce(c.last_message_at, c.updated_at) < ^stalled_before)
    |> Repo.all()
    |> Enum.each(
      &terminate(
        &1,
        "stalled",
        "No progress for #{@stall_minutes} minutes; the run was marked failed."
      )
    )
  end

  @spec terminate(Conversation.t(), String.t(), String.t()) :: :ok
  defp terminate(%Conversation{} = conversation, error_key, message) do
    request_id = conversation.active_request_id

    conversation
    |> Conversation.changeset(%{
      active_status: nil,
      active_request_id: nil,
      gate_token: nil,
      gate_expires_at: nil,
      last_error: %{"reason" => error_key}
    })
    |> Repo.update()
    |> case do
      {:ok, updated} -> publish(updated, request_id, error_key, message)
      {:error, _changeset} -> :ok
    end
  end

  # request_id is nil only for a conversation this sweep should never have matched in the
  # first place (both queries require an in-flight active_status) — skipped defensively rather
  # than raised, since a broken publish must never stop the sweep from reconciling the row.
  @spec publish(Conversation.t(), String.t() | nil, String.t(), String.t()) :: :ok
  defp publish(_conversation, nil, _error_key, _message), do: :ok

  defp publish(%Conversation{} = conversation, request_id, error_key, message) do
    Publisher.publish(conversation, :error, request_id, %{
      errors: [%{key: error_key, message: message}]
    })
  end
end
