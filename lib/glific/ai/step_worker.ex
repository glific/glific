defmodule Glific.AI.StepWorker do
  @moduledoc """
  Runs exactly one `Glific.AI.Runtime.step/1` and persists its outcome. One Oban job is one
  step — never a whole run — so a deploy or a crash never loses more than the step in flight.

  ## Args

  `%{"conversation_id", "organization_id", "user_id", "seq"}`, plus an optional `"decision"`
  (`"accepted" | "rejected"`) — never a credential. Oban args are JSON in the database and
  surface in AppSignal job payloads; `Glific.AI.Credentials.fetch/2` is called fresh inside
  `perform/1` instead. `decision` is safe there for the same reason it is safe to log: it is a
  human's yes/no, not a secret. `seq` is the `ai_messages.seq` this job's first persisted
  message will take — assigned by whichever job enqueues this one (see "Sequencing" below),
  never recomputed here, so a replayed job (Oban's at-least-once delivery, or
  `Oban.Pro.Plugins.DynamicLifeline` rescuing an orphaned row) inserts at the same `seq` every
  time and `ai_messages`' unique `(conversation_id, seq)` index turns the replay into a no-op.

  When `decision` is present this job is a **resume job**: `perform/1` calls
  `Glific.AI.Runtime.resume/2` instead of `Glific.AI.Runtime.step/1`, but is otherwise the same
  job — same actor setup, same watchdog, same single `Ecto.Multi`, same idempotent `seq`
  insert, same publish-after-commit. `GlificWeb.Resolvers.AI.resolve_ai_request/3` is the only
  place that enqueues one, right after it clears the gate.

  ## Guard order

  1. `Repo.put_organization_id/1` — **never `Repo.put_process_state/1`**. That call would make
     this job run as the organization's root user; `Glific.AI.Actor.put!/2` (next) is what
     establishes the *requesting* user's identity instead. See `Glific.AI.Actor`'s moduledoc.
  2. `Glific.AI.Actor.put!/2`
  3. Fetch the conversation, scoped to `user_id`.
  4. **Status guard.** A plain step (`decision` absent) is admitted when `active_status` is
     `:queued` or `:running`; a resume job (`decision` present) is admitted only when it is
     exactly `:running`, never `:queued` — `:queued` means "no first step has run yet", a state
     a resume job can never legitimately observe since `resolve_ai_request/3` sets
     `active_status: :running` in the same update that clears the gate, before this job is even
     enqueued. Anything else — a plain step arriving while `:awaiting_confirmation` (superseded
     by the gate it should have hit), a resume job arriving after the run already finished,
     suspended again, or was cancelled — is a late or duplicate job and returns `:ok` without
     doing anything else. This is what makes such a job harmless instead of corrupting a
     conversation someone else is now driving.
  5. **Budget guard** — applies to a plain step only: `step_count >= max_steps` fails the run
     permanently rather than looping forever on a skill that never converges. A resume job
     bypasses it. The gate is a human checkpoint, not the runaway autonomous looping `max_steps`
     exists to bound, and the decision itself never calls the model; honoring an explicit
     accept/reject should never be silently discarded by a budget technicality. Consistently,
     persisting a resume outcome (see step 8) does not increment `step_count` — the budget is
     spent by model/tool steps, and the one ordinary step a `{:continue, _}` resume schedules
     next is still subject to this same guard on its own turn.
  6. `Glific.AI.build_context/1`, `Glific.AI.Skill.Registry.fetch/1`,
     `Glific.AI.Credentials.fetch/2` build this step's `Glific.AI.Runtime.State`.
  7. `Glific.AI.Runtime.step/1` (or `resume/2`) runs under a hard 45s wall clock
     (`Task.yield/2` + `Task.shutdown/2`) — comfortably inside `shutdown_grace_period` (60s,
     `config/config.exs`), so a step that is killed mid-flight is always killed *by* the
     deploy/crash, never by racing its own timeout past Oban's.
  8. The outcome is persisted in **one `Ecto.Multi`**: every message at its assigned `seq`
     (`on_conflict: :nothing`), the conversation's in-flight state, and — for `:continue` only —
     the next `StepWorker` job via `Oban.insert/3` (always a plain step: `decision` is never
     forwarded past the resume that consumed it). Oban shares `Glific.Repo`
     (`config/config.exs`), so "the conversation advanced but the next step never got
     scheduled" is not a state this transaction can leave behind. An event is published only
     after that transaction commits. A resume's `:done`/`:continue` outcome also clears
     `pending_proposal` — the decision it held has now been acted on.

  ## Sequencing

  A `:continue` step persists `length(message_attrs)` rows starting at this job's `seq`, then
  schedules the next job with `seq: this_seq + length(message_attrs)`. The very first job of a
  run is enqueued by whoever starts it (outside this module) with `seq` one past the seed user
  message it just inserted.

  ## Termination

  `:done` clears `active_request_id`/`active_status` — no next job; the run is over. `:suspend`
  (only ever returned by `Glific.AI.Runtime.step/1`, never `resume/2` — see its moduledoc) sets
  `active_status: :awaiting_confirmation`, a one-time `gate_token`
  (`:crypto.strong_rand_bytes(24) |> Base.url_encode64()`) and `gate_expires_at` — no next job;
  the loop is now driven by a user's decision, not this worker. A `{:transient_error, reason}`
  from `step/1`/`resume/2` is returned as `{:error, reason}` so Oban retries within
  `max_attempts`. A `{:permanent_error, reason}` — and the budget guard — mark the run failed
  and return `:ok`, deliberately, so a run that cannot succeed does not burn retries or land in
  `discarded` where nothing would ever look at it again.

  **Never query `oban_jobs` for AI run status.**
  `Oban.Pro.Plugins.DynamicPruner` (`config/config.exs`) deletes job rows five minutes after
  completion — `ai_conversations.active_status`/`active_request_id` is the only durable place
  a run's status lives. `Glific.AI.Sweeper` (via `Glific.Jobs.MinuteWorker`) is what reconciles
  a conversation whose job row is long gone.
  """

  use Oban.Worker,
    queue: :ai_runtime,
    max_attempts: 3,
    unique: [
      fields: [:args],
      keys: [:conversation_id, :seq],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Glific.{
    AI,
    AI.Actor,
    AI.Codec,
    AI.Conversation,
    AI.Credentials,
    AI.Message,
    AI.Publisher,
    AI.Runtime,
    AI.Runtime.State,
    AI.Skill.Registry,
    AI.Telemetry.Context,
    Enums.AIRequestStatus,
    Repo,
    SafeLog
  }

  alias Glific.AI.StepWorker

  @step_timeout_ms 45_000

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{
        args:
          %{
            "conversation_id" => conversation_id,
            "organization_id" => organization_id,
            "user_id" => user_id,
            "seq" => seq
          } = args
      }) do
    Repo.put_organization_id(organization_id)
    user = Actor.put!(organization_id, user_id)
    conversation = AI.get_conversation!(conversation_id, user_id)
    decision = parse_decision(Map.get(args, "decision"))

    cond do
      not status_ready?(conversation.active_status, decision) ->
        :ok

      is_nil(decision) and conversation.step_count >= conversation.max_steps ->
        fail_permanently(conversation, "step budget exhausted")

      true ->
        run(conversation, user, organization_id, seq, decision)
    end
  end

  @spec parse_decision(String.t() | nil) :: :accepted | :rejected | nil
  defp parse_decision(nil), do: nil
  defp parse_decision("accepted"), do: :accepted
  defp parse_decision("rejected"), do: :rejected

  @spec status_ready?(AIRequestStatus.t() | nil, :accepted | :rejected | nil) :: boolean()
  defp status_ready?(:running, _decision), do: true
  defp status_ready?(:queued, nil), do: true
  defp status_ready?(_status, _decision), do: false

  @spec run(
          Conversation.t(),
          Glific.Users.User.t(),
          non_neg_integer(),
          non_neg_integer(),
          :accepted | :rejected | nil
        ) :: :ok | {:error, term()}
  defp run(conversation, user, organization_id, seq, decision) do
    with {:ok, skill} <- Registry.fetch(conversation.skill),
         {:ok, context} <- AI.build_context(conversation.id),
         {:ok, api_key} <- Credentials.fetch(organization_id, skill.provider()) do
      state =
        State.new(
          conversation: conversation,
          skill: skill,
          user: user,
          context: context,
          step_index: seq,
          organization_id: organization_id,
          api_key: api_key
        )

      state
      |> run_with_timeout(decision)
      |> handle_result(conversation, seq, decision)
    else
      {:error, reason} -> fail_permanently(conversation, reason)
    end
  end

  @spec run_with_timeout(State.t(), :accepted | :rejected | nil) :: Runtime.result()
  defp run_with_timeout(%State{} = state, decision) do
    # The watchdog runs the step in a fresh process, which starts with an empty process
    # dictionary — no organization id, no acting user, no AI telemetry caller context. Without
    # this the first Repo call raises, every tool invocation fails Actor.assert!/2, and any
    # OpenTelemetry span this step opens carries no glific.*/ai.* attributes (see
    # Glific.AI.Telemetry.Context).
    task =
      Task.async(fn ->
        Actor.reinstate!(state.organization_id, state.user)

        Context.put(%{
          organization_id: state.organization_id,
          user_id: state.user.id,
          request_id: state.conversation.active_request_id,
          skill: state.skill.name(),
          step_index: state.step_index,
          conversation_id: state.conversation.id
        })

        if decision, do: Runtime.resume(state, decision), else: Runtime.step(state)
      end)

    case Task.yield(task, @step_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _timed_out_or_killed -> {:transient_error, :step_timeout}
    end
  end

  @spec handle_result(
          Runtime.result(),
          Conversation.t(),
          non_neg_integer(),
          :accepted | :rejected | nil
        ) :: :ok | {:error, term()}
  defp handle_result({:continue, state, message_attrs}, conversation, seq, decision),
    do: persist_continue(state, conversation, seq, message_attrs, decision)

  defp handle_result({:suspend, state, proposal, message_attrs}, conversation, seq, nil),
    do: persist_suspend(state, conversation, seq, message_attrs, proposal)

  defp handle_result({:done, _state, result, message_attrs}, conversation, seq, decision),
    do: persist_done(conversation, seq, message_attrs, result, decision)

  defp handle_result({:transient_error, reason}, _conversation, _seq, _decision),
    do: {:error, reason}

  defp handle_result({:permanent_error, reason}, conversation, _seq, _decision),
    do: fail_permanently(conversation, reason)

  @spec persist_continue(
          State.t(),
          Conversation.t(),
          non_neg_integer(),
          [map()],
          :accepted | :rejected | nil
        ) :: :ok | {:error, term()}
  defp persist_continue(%State{} = state, conversation, seq, message_attrs, decision) do
    next_seq = seq + length(message_attrs)
    request_id = conversation.active_request_id

    next_job =
      StepWorker.new(%{
        conversation_id: conversation.id,
        organization_id: conversation.organization_id,
        user_id: state.user.id,
        seq: next_seq
      })

    conversation_attrs =
      %{
        active_status: :running,
        step_count: bump_step_count(conversation.step_count, decision)
      }
      |> put_resolved_proposal(decision)

    Ecto.Multi.new()
    |> insert_messages(conversation, seq, message_attrs)
    |> Ecto.Multi.update(:conversation, Conversation.changeset(conversation, conversation_attrs))
    |> Oban.insert(:next_step, next_job)
    |> Repo.transaction()
    |> case do
      {:ok, %{conversation: updated}} ->
        publish_messages(updated, request_id, seq, message_attrs)
        :ok

      {:error, _failed_operation, reason, _changes} ->
        {:error, reason}
    end
  end

  @spec bump_step_count(non_neg_integer(), :accepted | :rejected | nil) :: non_neg_integer()
  defp bump_step_count(step_count, nil), do: step_count + 1
  defp bump_step_count(step_count, _decision), do: step_count

  # A resumed run has just acted on `pending_proposal` (see Glific.AI.Runtime.resume/2's
  # moduledoc section) — clearing it here is what stops the conversation from still looking
  # "awaiting confirmation" in `pending_proposal` after the gate has actually resolved. A plain
  # step never had one set (only `persist_suspend/5` sets it), so it is left untouched.
  @spec put_resolved_proposal(map(), :accepted | :rejected | nil) :: map()
  defp put_resolved_proposal(attrs, nil), do: attrs
  defp put_resolved_proposal(attrs, _decision), do: Map.put(attrs, :pending_proposal, nil)

  @spec persist_suspend(State.t(), Conversation.t(), non_neg_integer(), [map()], map()) ::
          :ok | {:error, term()}
  defp persist_suspend(%State{} = state, conversation, seq, message_attrs, proposal) do
    request_id = conversation.active_request_id
    gate_token = :crypto.strong_rand_bytes(24) |> Base.url_encode64()

    Ecto.Multi.new()
    |> insert_messages(conversation, seq, message_attrs)
    |> Ecto.Multi.update(
      :conversation,
      Conversation.changeset(conversation, %{
        active_status: :awaiting_confirmation,
        step_count: conversation.step_count + 1,
        gate_token: gate_token,
        gate_expires_at: gate_expires_at(state.skill),
        pending_proposal: proposal
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{conversation: updated}} ->
        publish_messages(updated, request_id, seq, message_attrs)
        publish(updated, :proposal, request_id, %{payload: proposal})
        :ok

      {:error, _failed_operation, reason, _changes} ->
        {:error, reason}
    end
  end

  @spec persist_done(
          Conversation.t(),
          non_neg_integer(),
          [map()],
          term(),
          :accepted | :rejected | nil
        ) :: :ok | {:error, term()}
  defp persist_done(conversation, seq, message_attrs, result, decision) do
    request_id = conversation.active_request_id

    conversation_attrs =
      %{
        active_status: nil,
        active_request_id: nil,
        step_count: bump_step_count(conversation.step_count, decision)
      }
      |> put_resolved_proposal(decision)

    Ecto.Multi.new()
    |> insert_messages(conversation, seq, message_attrs)
    |> Ecto.Multi.update(:conversation, Conversation.changeset(conversation, conversation_attrs))
    |> Repo.transaction()
    |> case do
      {:ok, %{conversation: updated}} ->
        publish_messages(updated, request_id, seq, message_attrs)
        publish(updated, :final, request_id, %{payload: result_payload(result)})
        :ok

      {:error, _failed_operation, reason, _changes} ->
        {:error, reason}
    end
  end

  @spec fail_permanently(Conversation.t(), term()) :: :ok
  defp fail_permanently(conversation, reason) do
    request_id = conversation.active_request_id
    safe_reason = SafeLog.safe_inspect(reason)

    conversation
    |> Conversation.changeset(%{
      active_status: nil,
      active_request_id: nil,
      last_error: %{"reason" => safe_reason}
    })
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        publish(updated, :error, request_id, %{errors: [%{key: "error", message: safe_reason}]})

      {:error, _changeset} ->
        :ok
    end

    :ok
  end

  @spec insert_messages(Ecto.Multi.t(), Conversation.t(), non_neg_integer(), [map()]) ::
          Ecto.Multi.t()
  defp insert_messages(multi, conversation, seq, message_attrs) do
    message_attrs
    |> Enum.with_index(seq)
    |> Enum.reduce(multi, fn {attrs, message_seq}, multi ->
      changeset =
        Message.changeset(
          %Message{},
          attrs
          |> Map.put(:seq, message_seq)
          |> Map.put(:conversation_id, conversation.id)
          |> Map.put(:organization_id, conversation.organization_id)
        )

      Ecto.Multi.insert(multi, {:message, message_seq}, changeset,
        on_conflict: :nothing,
        conflict_target: [:conversation_id, :seq]
      )
    end)
  end

  @spec gate_expires_at(module()) :: DateTime.t()
  defp gate_expires_at(skill) do
    ttl_seconds =
      case skill.gate_policy() do
        {:on_final, ttl} -> ttl
        :none -> 0
      end

    DateTime.utc_now() |> DateTime.add(ttl_seconds, :second) |> DateTime.truncate(:second)
  end

  # One `:message` event per persisted row, each carrying its own `seq` — see
  # Glific.AI.Publisher's moduledoc: `:delta`/`:message` carry `seq` so the client knows which
  # bubble to append to. A tool batch can persist several rows in one step; each gets its own
  # event rather than one event describing all of them.
  @spec publish_messages(Conversation.t(), String.t() | nil, non_neg_integer(), [map()]) :: :ok
  defp publish_messages(conversation, request_id, base_seq, message_attrs) do
    message_attrs
    |> Enum.with_index(base_seq)
    |> Enum.each(fn {attrs, message_seq} ->
      publish(conversation, :message, request_id, %{
        seq: message_seq,
        payload: %{"role" => Atom.to_string(attrs.role), "parts" => attrs.parts}
      })
    end)
  end

  # A :done result is either the raw final ReqLLM.Message (no output_schema) or an
  # already-JSON-safe map from Glific.AI.Model.object/3 (output_schema present) — see
  # Glific.AI.Runtime's moduledoc. Either way, the published payload must be plain JSON.
  @spec result_payload(term()) :: map()
  defp result_payload(%ReqLLM.Message{} = message) do
    case Codec.encode(message) do
      {:ok, parts} -> %{"parts" => parts}
      {:error, _reason} -> %{}
    end
  end

  defp result_payload(result) when is_map(result), do: result
  defp result_payload(_other), do: %{}

  # request_id is nil only if a conversation reaches here with no in-flight run at all, which
  # every guard above is meant to prevent — skipped rather than raised, since a broken publish
  # must never take down a step that otherwise persisted successfully.
  @spec publish(Conversation.t(), Publisher.event(), String.t() | nil, map()) :: :ok
  defp publish(_conversation, _event, nil, _fields), do: :ok

  defp publish(%Conversation{} = conversation, event, request_id, fields)
       when is_binary(request_id),
       do: Publisher.publish(conversation, event, request_id, fields)
end
