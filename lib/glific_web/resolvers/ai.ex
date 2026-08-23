defmodule GlificWeb.Resolvers.AI do
  @moduledoc """
  Resolver for the AI agent runtime's client-facing GraphQL surface: dispatching a skill run
  (`startAiRequest`), resolving a propose→confirm gate (`resolveAiRequest`), cancelling an
  in-flight run (`cancelAiRequest`), and the conversation/message reads that rebuild a
  transcript after a lost subscription (`aiConversations`/`aiConversation`/`aiMessages`).

  Every mutation here only validates, acks, or flips state — the actual model call and tool
  execution run on `Glific.AI.StepWorker`, driven from `Glific.AI.Runtime`. `enqueue_step/3`
  seeds the run's first message and schedules `Glific.AI.StepWorker`'s first job.
  `enqueue_resume/3` schedules the job that carries a resolved gate's decision back into the
  run — see its doc and `Glific.AI.StepWorker`'s moduledoc ("Args", "Guard order") for how that
  job is told apart from an ordinary step.
  """

  alias Glific.{
    AI,
    AI.Codec,
    AI.Conversation,
    AI.Publisher,
    AI.Skill,
    AI.Skill.Registry,
    AI.StepWorker,
    Users.User
  }

  alias GlificWeb.Schema.Middleware.Authorize

  @doc "Fetches one AI conversation by id, scoped to its creator."
  @spec ai_conversation(Absinthe.Resolution.t(), %{id: any()}, %{context: map()}) ::
          {:ok, map()} | {:error, String.t()}
  def ai_conversation(_, %{id: id}, %{context: %{current_user: user}}) do
    case AI.fetch_conversation(id, user.id) do
      {:ok, conversation} -> {:ok, %{conversation: conversation}}
      {:error, _reason} -> {:error, "Conversation not found."}
    end
  end

  @doc "Lists the caller's AI conversations for the chat list."
  @spec ai_conversations(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [Conversation.t()]}
  def ai_conversations(_, args, %{context: %{current_user: user}}) do
    filter = args |> Map.get(:filter, %{}) |> Map.put(:user_id, user.id)
    {:ok, AI.list_conversations(Map.put(args, :filter, filter))}
  end

  @doc "Lists a conversation's messages in seq order, scoped to the caller."
  @spec ai_messages(Absinthe.Resolution.t(), %{conversation_id: any()}, %{context: map()}) ::
          {:ok, [AI.Message.t()]} | {:error, String.t()}
  def ai_messages(_, %{conversation_id: conversation_id} = args, %{
        context: %{current_user: user}
      }) do
    case AI.fetch_conversation(conversation_id, user.id) do
      {:ok, conversation} ->
        {:ok, AI.list_messages(conversation.id, Map.take(args, [:opts]))}

      {:error, _reason} ->
        {:error, "Conversation not found."}
    end
  end

  @doc """
  Dispatches a skill run: resolves the skill, authorizes the caller against its
  `required_role/0`, validates the caller-supplied input, creates or continues the
  conversation, and acks immediately with status "queued".
  """
  @spec start_ai_request(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def start_ai_request(_, %{input: params}, %{context: %{current_user: user}}) do
    with {:ok, skill} <- Registry.fetch(params.skill),
         :ok <- authorize_skill(skill, user),
         :ok <- ensure_skill_enabled(skill, user),
         {:ok, validated_input} <- skill.validate_input(params.input),
         {:ok, conversation} <- get_or_create_conversation(params, skill, user),
         :ok <- ensure_idle(conversation),
         request_id <- Ecto.UUID.generate(),
         {:ok, conversation} <-
           AI.update_conversation(conversation, %{
             active_request_id: request_id,
             active_status: :queued
           }) do
      Publisher.publish(conversation, :queued, request_id)
      enqueue_step(conversation, validated_input, request_id)
      {:ok, ack(request_id, conversation.id, "queued")}
    else
      {:error, :unknown_skill} ->
        {:ok, error_ack("skill", "Unknown skill.")}

      {:error, :forbidden} ->
        {:ok, error_ack("skill", "You do not have permission to use this skill.")}

      {:error, :feature_disabled} ->
        {:ok, error_ack("skill", "This skill is not enabled for your organization.")}

      {:error, :busy} ->
        {:ok,
         error_ack("conversation_id", "A request is already in progress for this conversation.")}

      {:error, :skill_mismatch} ->
        {:ok, error_ack("conversation_id", "This conversation belongs to a different skill.")}

      {:error, reason} when is_binary(reason) ->
        {:ok, error_ack("input", reason)}

      {:error, %Ecto.Changeset{}} = error ->
        error

      {:error, _reason} ->
        {:ok, error_ack("conversation_id", "Conversation not found.")}
    end
  end

  @doc """
  Resolves the propose→confirm gate for a conversation awaiting human confirmation. Verifies
  the conversation belongs to the caller, that `gate_token` matches (constant-time comparison)
  and has not expired, and that a confirmation is actually pending, before touching anything.
  """
  @spec resolve_ai_request(
          Absinthe.Resolution.t(),
          %{conversation_id: any(), gate_token: String.t(), decision: String.t()},
          %{context: map()}
        ) :: {:ok, map()} | {:error, any()}
  def resolve_ai_request(
        _,
        %{conversation_id: id, gate_token: gate_token, decision: decision},
        %{context: %{current_user: user}}
      ) do
    with {:ok, conversation} <- AI.fetch_conversation(id, user.id),
         {:ok, decision} <- parse_decision(decision),
         :ok <- verify_gate(conversation, gate_token),
         request_id = conversation.active_request_id,
         {:ok, conversation} <-
           AI.update_conversation(conversation, %{
             gate_token: nil,
             gate_expires_at: nil,
             active_status: :running
           }) do
      enqueue_resume(conversation, decision, request_id)
      {:ok, ack(request_id, conversation.id, "running")}
    else
      {:error, :invalid_decision} ->
        {:ok, error_ack("decision", "Decision must be accepted or rejected.")}

      {:error, :invalid_gate} ->
        {:ok, error_ack("gate_token", "This confirmation token is invalid or has expired.")}

      {:error, %Ecto.Changeset{}} = error ->
        error

      {:error, _reason} ->
        {:ok, error_ack("conversation_id", "Conversation not found.")}
    end
  end

  @doc """
  Cancels an in-flight run. Flips `active_status` to "cancelled" and clears any pending gate
  token so it can no longer be resolved; the next step job's own guard (checking
  `active_status`) is what actually stops the run from continuing. A no-op, not an error, when
  there is nothing in flight.
  """
  @spec cancel_ai_request(Absinthe.Resolution.t(), %{conversation_id: any()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def cancel_ai_request(_, %{conversation_id: id}, %{context: %{current_user: user}}) do
    with {:ok, conversation} <- AI.fetch_conversation(id, user.id),
         request_id = conversation.active_request_id,
         {:ok, conversation} <- cancel_if_active(conversation) do
      if request_id,
        do:
          Publisher.publish(conversation, :final, request_id, %{payload: %{status: "cancelled"}})

      {:ok, ack(request_id, conversation.id, to_string(conversation.active_status || "idle"))}
    else
      {:error, %Ecto.Changeset{}} = error -> error
      {:error, _reason} -> {:ok, error_ack("conversation_id", "Conversation not found.")}
    end
  end

  @spec authorize_skill(module(), User.t()) :: :ok | {:error, :forbidden}
  defp authorize_skill(skill, user) do
    if Authorize.valid_role?(user.roles, skill.required_role()),
      do: :ok,
      else: {:error, :forbidden}
  end

  @spec ensure_skill_enabled(module(), User.t()) :: :ok | {:error, :feature_disabled}
  defp ensure_skill_enabled(skill, user) do
    if Skill.enabled?(skill, user.organization_id),
      do: :ok,
      else: {:error, :feature_disabled}
  end

  @spec get_or_create_conversation(map(), module(), User.t()) ::
          {:ok, Conversation.t()} | {:error, :skill_mismatch} | {:error, Ecto.Changeset.t()}
  defp get_or_create_conversation(%{conversation_id: id}, skill, user) when not is_nil(id) do
    with {:ok, conversation} <- AI.fetch_conversation(id, user.id) do
      if conversation.skill == skill.name(),
        do: {:ok, conversation},
        else: {:error, :skill_mismatch}
    end
  end

  defp get_or_create_conversation(_params, skill, user) do
    AI.create_conversation(%{
      skill: skill.name(),
      max_steps: skill.max_steps(),
      codec_version: Codec.version(),
      user_id: user.id,
      organization_id: user.organization_id
    })
  end

  @spec ensure_idle(Conversation.t()) :: :ok | {:error, :busy}
  defp ensure_idle(%Conversation{active_status: nil}), do: :ok
  defp ensure_idle(%Conversation{}), do: {:error, :busy}

  @spec parse_decision(String.t()) :: {:ok, :accepted | :rejected} | {:error, :invalid_decision}
  defp parse_decision("accepted"), do: {:ok, :accepted}
  defp parse_decision("rejected"), do: {:ok, :rejected}
  defp parse_decision(_decision), do: {:error, :invalid_decision}

  @spec verify_gate(Conversation.t(), String.t()) :: :ok | {:error, :invalid_gate}
  defp verify_gate(
         %Conversation{active_status: :awaiting_confirmation} = conversation,
         gate_token
       ) do
    if gate_token_matches?(conversation, gate_token) and gate_not_expired?(conversation),
      do: :ok,
      else: {:error, :invalid_gate}
  end

  defp verify_gate(_conversation, _gate_token), do: {:error, :invalid_gate}

  @spec gate_token_matches?(Conversation.t(), String.t()) :: boolean()
  defp gate_token_matches?(%Conversation{gate_token: stored}, provided)
       when is_binary(stored) and is_binary(provided),
       do: Plug.Crypto.secure_compare(stored, provided)

  defp gate_token_matches?(_conversation, _provided), do: false

  @spec gate_not_expired?(Conversation.t()) :: boolean()
  defp gate_not_expired?(%Conversation{gate_expires_at: %DateTime{} = expires_at}),
    do: DateTime.compare(DateTime.utc_now(), expires_at) == :lt

  defp gate_not_expired?(_conversation), do: false

  @spec cancel_if_active(Conversation.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  defp cancel_if_active(%Conversation{active_status: status} = conversation)
       when status in [:queued, :running, :awaiting_confirmation] do
    AI.update_conversation(conversation, %{
      active_status: :cancelled,
      gate_token: nil,
      gate_expires_at: nil
    })
  end

  defp cancel_if_active(%Conversation{} = conversation), do: {:ok, conversation}

  @spec ack(String.t() | nil, pos_integer(), String.t()) :: map()
  defp ack(request_id, conversation_id, status),
    do: %{request_id: request_id, conversation_id: conversation_id, status: status, errors: []}

  @spec error_ack(String.t(), String.t()) :: map()
  defp error_ack(key, message),
    do: %{
      request_id: nil,
      conversation_id: nil,
      status: nil,
      errors: [%{key: key, message: message}]
    }

  # Glific.AI.Runtime derives a skill's `input` from the conversation's first stored message,
  # as %{"message" => <that message's text>} (see its moduledoc, "Deriving input") — so a run
  # cannot start until that seed row exists. Only skills using that "message" convention are
  # runnable today; extending `input` beyond a single "message" key is Runtime's documented
  # limitation, not something this resolver can work around.
  @spec enqueue_step(Conversation.t(), map(), String.t()) :: :ok
  defp enqueue_step(conversation, validated_input, request_id) do
    seed_seq = AI.count_messages(conversation.id) + 1
    message_text = Map.get(validated_input, "message", "")

    with {:ok, parts} <- Codec.encode(ReqLLM.Context.user(message_text)),
         {:ok, _status} <-
           AI.append_message(conversation, %{seq: seed_seq, role: :user, parts: parts}),
         {:ok, _job} <-
           %{
             conversation_id: conversation.id,
             organization_id: conversation.organization_id,
             user_id: conversation.user_id,
             seq: seed_seq + 1
           }
           |> StepWorker.new()
           |> Oban.insert() do
      :ok
    else
      {:error, reason} ->
        Glific.log_error(
          "Glific.AI.StepWorker enqueue failed for conversation #{conversation.id}, " <>
            "request #{request_id}: #{Glific.SafeLog.safe_inspect(reason)}"
        )

        :ok
    end
  end

  # `Glific.AI.Runtime.resume/2` derives everything else it needs (the pending proposal,
  # `skill.on_decision/3`) from the conversation row itself, so this job only has to carry the
  # decision alongside the same identifying args `enqueue_step/3` sends — `seq` computed the
  # same way, from `AI.count_messages/1`, since a resume can persist a message (the decision
  # itself; see Runtime.resume/2's moduledoc) before the run's next ordinary step.
  @spec enqueue_resume(Conversation.t(), :accepted | :rejected, String.t() | nil) :: :ok
  defp enqueue_resume(conversation, decision, request_id) do
    seq = AI.count_messages(conversation.id) + 1

    %{
      conversation_id: conversation.id,
      organization_id: conversation.organization_id,
      user_id: conversation.user_id,
      seq: seq,
      decision: Atom.to_string(decision)
    }
    |> StepWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Glific.log_error(
          "Glific.AI.StepWorker resume enqueue failed for conversation #{conversation.id}, " <>
            "request #{request_id}: #{Glific.SafeLog.safe_inspect(reason)}"
        )

        :ok
    end
  end
end
