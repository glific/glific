defmodule Glific.AI.Run do
  @moduledoc """
  Drives a skill to completion **inside the calling process**, returning its final result
  directly instead of publishing it.

  `Glific.AI.StepWorker` is the durable path: one Oban job per step, survives a deploy, streams
  progress over a subscription. It is the right shape for a multi-step run a human watches. It
  is the wrong shape for two callers:

    * **A one-shot skill behind a button.** A skill with no tools makes exactly one model call.
      Routing it through a queue, a subscription and a reconnect path costs a great deal of
      client machinery to reproduce a request/response the caller already had.
    * **Evals.** An eval asserts on a skill's *output*. Driving Oban from ExUnit and then
      reconstructing the result from published events tests the queue, not the skill.

  Both want the same thing: run the skill, give me what it returned. That is this module.

  ## What is and is not shared with the durable path

  Shared: `Glific.AI.Runtime.step/1`, `Glific.AI.Codec`, `Glific.AI.Actor`, `Glific.AI.Model`,
  `Glific.AI.Tool.Runner`, and the `ai_conversations` / `ai_messages` rows — a sync run leaves
  exactly the transcript a durable run would, which is what keeps it usable as an eval replay
  corpus and an audit trail.

  Not shared: no Oban job, no `Glific.AI.Publisher` event, and **no crash recovery**. If the
  process dies mid-run the transcript stops where it stopped and nothing resumes it. That is
  acceptable precisely because the caller is a live GraphQL request or a test — both of which
  died with it.

  ## Bounds

  The whole run happens inside one caller's timeout, so the step budget is not merely a
  safety net here — it is the latency contract. A skill invoked through `sync/3` should have a
  small `max_steps/0` and few or no tools, or the caller waits for every step in series.

  A gated skill (`gate_policy/0` returning `{:on_final, _}`) is refused outright: the gate
  exists to hold a proposal for a human decision that arrives minutes later, which a
  synchronous caller cannot wait for. Gated skills use `startAiRequest`.
  """

  alias Glific.AI
  alias Glific.AI.Actor
  alias Glific.AI.Codec
  alias Glific.AI.Conversation
  alias Glific.AI.Credentials
  alias Glific.AI.Runtime
  alias Glific.AI.Runtime.State
  alias Glific.AI.Skill
  alias Glific.AI.Skill.Registry
  alias Glific.AI.Telemetry.Context
  alias Glific.Users.Roles
  alias Glific.Users.User

  @typedoc "A completed synchronous run."
  @type outcome :: %{
          result: term(),
          conversation: Conversation.t(),
          request_id: String.t(),
          steps: non_neg_integer()
        }

  @typedoc "Why a synchronous run did not produce a result."
  @type error ::
          :unknown_skill
          | :forbidden
          | :feature_disabled
          | :gated_skill
          | :step_budget_exhausted
          | term()

  @doc """
  Runs `skill_name` against `input` as `user`, blocking until the skill produces its final
  result.
  """
  @spec sync(String.t(), map(), User.t()) :: {:ok, outcome()} | {:error, error()}
  def sync(skill_name, input, %User{} = user) do
    first_step_seq = 2

    # Actor.reinstate!/2 re-establishes org/user Repo context for this process; this call is
    # its telemetry counterpart, giving Glific.AI.Telemetry.OTelAdapter a caller context to
    # attach to any span `loop/5` opens below. Set right after `seed/3` rather than immediately
    # next to `reinstate!/2` — unlike Glific.AI.StepWorker's per-task context, a sync run makes
    # every model call in this same process, and the conversation/request id this context
    # carries do not exist until `seed/3` creates the row.
    with {:ok, skill} <- Registry.fetch(skill_name),
         :ok <- authorize(skill, user),
         :ok <- flag_enabled(skill, user),
         :ok <- refuse_gated(skill),
         {:ok, validated} <- skill.validate_input(input),
         :ok <- Actor.reinstate!(user.organization_id, user),
         {:ok, api_key} <- Credentials.fetch(user.organization_id, skill.provider()),
         {:ok, conversation} <- seed(skill, validated, user),
         :ok <- put_telemetry_context(conversation, skill, user, first_step_seq) do
      conversation
      |> loop(skill, user, api_key, first_step_seq)
      |> finish(conversation)
    end
  end

  @spec put_telemetry_context(Conversation.t(), module(), User.t(), non_neg_integer()) :: :ok
  defp put_telemetry_context(conversation, skill, %User{} = user, step_index) do
    Context.put(%{
      organization_id: conversation.organization_id,
      user_id: user.id,
      request_id: conversation.active_request_id,
      skill: skill.name(),
      step_index: step_index,
      conversation_id: conversation.id
    })
  end

  @spec authorize(module(), User.t()) :: :ok | {:error, :forbidden}
  defp authorize(skill, %User{roles: roles}) do
    if Roles.highest_rank(roles) >= Roles.rank(skill.required_role()),
      do: :ok,
      else: {:error, :forbidden}
  end

  @spec flag_enabled(module(), User.t()) :: :ok | {:error, :feature_disabled}
  defp flag_enabled(skill, %User{organization_id: organization_id}) do
    if Skill.enabled?(skill, organization_id),
      do: :ok,
      else: {:error, :feature_disabled}
  end

  @spec refuse_gated(module()) :: :ok | {:error, :gated_skill}
  defp refuse_gated(skill) do
    case skill.gate_policy() do
      :none -> :ok
      {:on_final, _ttl} -> {:error, :gated_skill}
    end
  end

  @spec seed(module(), map(), User.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | term()}
  defp seed(skill, validated_input, %User{} = user) do
    with {:ok, conversation} <-
           AI.create_conversation(%{
             skill: skill.name(),
             max_steps: skill.max_steps(),
             codec_version: Codec.version(),
             active_request_id: Ecto.UUID.generate(),
             active_status: :running,
             user_id: user.id,
             organization_id: user.organization_id
           }) do
      seed_message(conversation, Map.get(validated_input, "message", ""))
    end
  end

  # A conversation is born :running, so a seed that fails after it exists must release the row
  # on the way out — nothing sweeps a synchronous run, and a row left at :running is one the
  # caller can never reuse.
  @spec seed_message(Conversation.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, term()}
  defp seed_message(%Conversation{} = conversation, message) do
    with {:ok, parts} <- Codec.encode(ReqLLM.Context.user(message)),
         {:ok, _written} <- AI.append_message(conversation, %{seq: 1, role: :user, parts: parts}) do
      {:ok, conversation}
    else
      {:error, reason} ->
        release(conversation, %{"reason" => Glific.SafeLog.safe_inspect(reason)})
        {:error, reason}
    end
  end

  @spec loop(Conversation.t(), module(), User.t(), String.t(), non_neg_integer()) ::
          {:ok, term(), Conversation.t()} | {:error, error()}
  defp loop(conversation, skill, user, api_key, seq) do
    with {:ok, context} <- AI.build_context(conversation.id) do
      [
        conversation: conversation,
        skill: skill,
        user: user,
        context: context,
        step_index: seq,
        organization_id: conversation.organization_id,
        api_key: api_key
      ]
      |> State.new()
      |> Runtime.step()
      |> advance(conversation, skill, user, api_key, seq)
    end
  end

  @spec advance(
          Runtime.result(),
          Conversation.t(),
          module(),
          User.t(),
          String.t(),
          non_neg_integer()
        ) :: {:ok, term(), Conversation.t()} | {:error, error()}
  defp advance({:continue, _state, message_attrs}, conversation, skill, user, api_key, seq) do
    with {:ok, advanced, next_seq} <- persist(conversation, seq, message_attrs) do
      if advanced.step_count >= advanced.max_steps,
        do: {:error, :step_budget_exhausted},
        else: loop(advanced, skill, user, api_key, next_seq)
    end
  end

  defp advance({:done, _state, result, message_attrs}, conversation, _skill, _user, _key, seq) do
    with {:ok, advanced, _next_seq} <- persist(conversation, seq, message_attrs) do
      {:ok, result, advanced}
    end
  end

  defp advance({:suspend, _state, _proposal, _attrs}, _conversation, _skill, _user, _key, _seq),
    do: {:error, :gated_skill}

  defp advance({:transient_error, reason}, _conversation, _skill, _user, _key, _seq),
    do: {:error, reason}

  defp advance({:permanent_error, reason}, _conversation, _skill, _user, _key, _seq),
    do: {:error, reason}

  @spec persist(Conversation.t(), non_neg_integer(), [map()]) ::
          {:ok, Conversation.t(), non_neg_integer()} | {:error, term()}
  defp persist(conversation, seq, message_attrs) do
    message_attrs
    |> Enum.with_index(seq)
    |> Enum.reduce_while(:ok, fn {attrs, message_seq}, :ok ->
      case AI.append_message(conversation, Map.put(attrs, :seq, message_seq)) do
        {:ok, _written} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> bump_step_count(conversation, seq + length(message_attrs))
      {:error, _reason} = error -> error
    end
  end

  @spec bump_step_count(Conversation.t(), non_neg_integer()) ::
          {:ok, Conversation.t(), non_neg_integer()} | {:error, Ecto.Changeset.t()}
  defp bump_step_count(conversation, next_seq) do
    case AI.update_conversation(conversation, %{step_count: conversation.step_count + 1}) do
      {:ok, updated} -> {:ok, updated, next_seq}
      {:error, _changeset} = error -> error
    end
  end

  # The conversation is released whatever happened, so a failed sync run leaves an idle row
  # rather than one wedged at :running that nothing will ever come back to clear.
  @spec finish({:ok, term(), Conversation.t()} | {:error, error()}, Conversation.t()) ::
          {:ok, outcome()} | {:error, error()}
  defp finish({:ok, result, conversation}, _seed) do
    {:ok, released} = release(conversation, nil)

    {:ok,
     %{
       result: result,
       conversation: released,
       request_id: conversation.active_request_id,
       steps: released.step_count
     }}
  end

  defp finish({:error, reason}, seed) do
    release(seed, %{"reason" => Glific.SafeLog.safe_inspect(reason)})
    {:error, reason}
  end

  @spec release(Conversation.t(), map() | nil) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  defp release(conversation, last_error) do
    AI.update_conversation(conversation, %{
      active_status: nil,
      active_request_id: nil,
      last_error: last_error
    })
  end
end
