defmodule Glific.AskGlific do
  @moduledoc """
  Ask Glific: dispatches staff questions to the `Glific.AI.Skills.AskGlific` skill on the
  in-process AI agent runtime, and serves the conversation/message history the Ask Glific chat
  UI reads back.

  This module keeps the historic `Glific.AskGlific` public API (`ask/2`, `submit_feedback/2`,
  `get_conversations/2`, `get_messages/3`) so `GlificWeb.Resolvers.AskGlific` and the frontend
  contract in `GlificWeb.Schema.AskGlificTypes` do not change, even though every call now goes
  through `Glific.AI` and `Glific.AI.StepWorker` instead of the retired Dify integration.

  `ask/2` does not return the answer. It validates the request, creates or continues an
  `ai_conversations` row, appends the question, and enqueues the first `Glific.AI.StepWorker`
  job — then returns immediately. The real answer arrives asynchronously on the legacy
  `ask_glific_response` subscription, translated from the runtime's `ai_request_event` topic by
  `Glific.AskGlific.Bridge`.
  """

  alias Glific.{
    AI,
    AI.Codec,
    AI.Conversation,
    AI.StepWorker,
    Flags,
    SafeLog,
    Users.Roles,
    Users.User
  }

  alias Glific.AI.Skills.AskGlific, as: AskGlificSkill

  defmodule Error do
    @moduledoc """
    Exception raised when Ask Glific fails to start a run.
    Reporting these to AppSignal lets us alert on the feature being unusable, as distinct from
    an individual model call failing (which the runtime reports on its own).
    """
    defexception [:message]
  end

  # AppSignal namespace for AskGlific errors (enables a dedicated error-rate trigger).
  @appsignal_namespace "ask_glific"

  @rate_limit_window_ms 60_000
  # Ask Glific is an interactive staff chat tool; 20 requests/minute per user comfortably covers
  # rapid back-and-forth without opening the runtime spine to abuse from a single account.
  @rate_limit_max_requests 20

  @doc """
  Starts (or continues) an Ask Glific run for `user`.

  Returns an immediate ack — `answer` is always `nil` here, the real answer is published later
  on the `ask_glific_response` subscription. `params` carries `:query` (required),
  `:conversation_id` (continues an existing conversation when present), `:page_url` (folded
  into the question text as model context, never used to resolve an organisation — the caller's
  own `organization_id` is the only source of tenant scoping) and `:request_id` (echoed back so
  a client can match the eventual publish to this call).
  """
  @spec ask(map(), User.t()) :: {:ok, map()} | {:error, atom() | String.t() | Ecto.Changeset.t()}
  def ask(params, user) do
    Glific.Metrics.increment("AskGlific Requests")

    with {:ok, query} <- validate_query(params),
         :ok <- ensure_enabled(user),
         :ok <- authorize_role(user),
         :ok <- check_rate_limit(user) do
      do_ask(
        query,
        Map.get(params, :conversation_id),
        Map.get(params, :page_url),
        correlation_id(params),
        user
      )
    end
  end

  # The client issues its own request id and drops every published event whose id does not match
  # it, because the subscription topic is org+user wide and a second tab's events arrive here
  # too (glific-frontend AskGlific.tsx). Generating our own id instead would leave the client
  # discarding its own answer and waiting forever.
  @spec correlation_id(map()) :: String.t()
  defp correlation_id(params) do
    case Map.get(params, :request_id) do
      id when is_binary(id) and id != "" -> id
      _absent -> Ecto.UUID.generate()
    end
  end

  @spec validate_query(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_query(params) do
    query = params |> Map.get(:query) |> to_string() |> String.trim()
    if query == "", do: {:error, "Query is required"}, else: {:ok, query}
  end

  # `Glific.AI.Skill.enabled?/2` alone would lose the `trusted_env?` fallback that
  # `Flags.get_ask_glific_enabled/1` provides — some organizations rely on that fallback rather
  # than the FunWithFlags toggle, and switching to `Skill.enabled?/2` here would be a silent
  # behaviour regression for them.
  @spec ensure_enabled(User.t()) :: :ok | {:error, :feature_disabled}
  defp ensure_enabled(user) do
    if Flags.get_ask_glific_enabled(%{id: user.organization_id}),
      do: :ok,
      else: {:error, :feature_disabled}
  end

  # `ask_glific_mutations` authorizes at :staff (a frozen GraphQL contract), but
  # `Glific.AI.Skills.AskGlific.required_role/0` is :manager — see that skill's moduledoc for
  # why. Enforcing the narrower role here is what actually makes that narrowing real.
  @spec authorize_role(User.t()) :: :ok | {:error, :forbidden}
  defp authorize_role(user) do
    if Roles.highest_rank(user.roles) >= Roles.rank(AskGlificSkill.required_role()),
      do: :ok,
      else: {:error, :forbidden}
  end

  @spec check_rate_limit(User.t()) :: :ok | {:error, :rate_limited}
  defp check_rate_limit(user) do
    case ExRated.check_rate(
           "ask_glific:#{user.id}",
           @rate_limit_window_ms,
           @rate_limit_max_requests
         ) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, :rate_limited}
    end
  end

  @spec do_ask(String.t(), String.t() | nil, String.t() | nil, String.t(), User.t()) ::
          {:ok, map()} | {:error, atom() | Ecto.Changeset.t()}
  defp do_ask(query, conversation_id, page_url, request_id, user) do
    start_time = System.monotonic_time(:millisecond)

    case start_run(query, conversation_id, page_url, request_id, user) do
      {:ok, _ack} = success ->
        record_outcome("success", elapsed_ms(start_time))
        success

      {:error, %Ecto.Changeset{}} = error ->
        latency_ms = elapsed_ms(start_time)
        record_outcome("failure", latency_ms)
        report_failure(user, latency_ms, "failed to start a run")
        error

      # :busy, :skill_mismatch and :not_found are expected client-caused declines, not system
      # failures — they don't get AppSignal noise.
      {:error, _reason} = error ->
        error
    end
  end

  @spec start_run(String.t(), String.t() | nil, String.t() | nil, String.t(), User.t()) ::
          {:ok, map()} | {:error, atom() | Ecto.Changeset.t()}
  defp start_run(query, conversation_id, page_url, request_id, user) do
    with {:ok, conversation} <- get_or_create_conversation(conversation_id, query, user),
         :ok <- ensure_idle(conversation),
         {:ok, conversation} <-
           AI.update_conversation(conversation, %{
             active_request_id: request_id,
             active_status: :queued
           }) do
      enqueue_step(conversation, query, page_url, request_id)
      {:ok, ack(conversation, request_id)}
    end
  end

  @spec get_or_create_conversation(String.t() | nil, String.t(), User.t()) ::
          {:ok, Conversation.t()} | {:error, :skill_mismatch | :not_found | Ecto.Changeset.t()}
  defp get_or_create_conversation(conversation_id, _query, user)
       when is_binary(conversation_id) and conversation_id != "" do
    with {:ok, id} <- parse_conversation_id(conversation_id),
         {:ok, conversation} <- AI.fetch_conversation(id, user.id) do
      if conversation.skill == AskGlificSkill.name(),
        do: {:ok, conversation},
        else: {:error, :skill_mismatch}
    else
      _not_found -> {:error, :not_found}
    end
  end

  defp get_or_create_conversation(_conversation_id, query, user) do
    AI.create_conversation(%{
      skill: AskGlificSkill.name(),
      title: AI.derive_title(query),
      max_steps: AskGlificSkill.max_steps(),
      codec_version: Codec.version(),
      user_id: user.id,
      organization_id: user.organization_id
    })
  end

  @spec parse_conversation_id(String.t()) :: {:ok, pos_integer()} | {:error, :not_found}
  defp parse_conversation_id(conversation_id) do
    case Integer.parse(conversation_id) do
      {id, ""} when id > 0 -> {:ok, id}
      _malformed -> {:error, :not_found}
    end
  end

  @spec ensure_idle(Conversation.t()) :: :ok | {:error, :busy}
  defp ensure_idle(%Conversation{active_status: nil}), do: :ok
  defp ensure_idle(%Conversation{}), do: {:error, :busy}

  # Mirrors `GlificWeb.Resolvers.AI.enqueue_step/3` exactly — same seed-message-then-job
  # sequence, same swallow-and-log failure handling — rather than inventing a second way to
  # start a run. `page_url` rides along inside the question text; it is model context only and
  # is never used to resolve the organisation (that always comes from `conversation`, which was
  # created/loaded scoped to `user`).
  @spec enqueue_step(Conversation.t(), String.t(), String.t() | nil, String.t()) :: :ok
  defp enqueue_step(conversation, query, page_url, request_id) do
    seed_seq = AI.count_messages(conversation.id) + 1
    message_text = with_page_url(query, page_url)

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
          "Glific.AskGlific enqueue failed for conversation #{conversation.id}, " <>
            "request #{request_id}: #{SafeLog.safe_inspect(reason)}"
        )

        :ok
    end
  end

  @spec with_page_url(String.t(), String.t() | nil) :: String.t()
  defp with_page_url(query, page_url) when is_binary(page_url) and page_url != "",
    do: query <> "\n\n[Page context: #{page_url}]"

  defp with_page_url(query, _page_url), do: query

  @spec ack(Conversation.t(), String.t()) :: map()
  defp ack(conversation, request_id) do
    %{
      answer: nil,
      conversation_id: to_string(conversation.id),
      conversation_name: conversation.title,
      message_id: nil,
      request_id: request_id,
      errors: []
    }
  end

  @spec elapsed_ms(integer()) :: non_neg_integer()
  defp elapsed_ms(start_time), do: System.monotonic_time(:millisecond) - start_time

  # Reports an Ask Glific run failing to start to AppSignal.
  @spec report_failure(User.t(), non_neg_integer(), String.t()) :: :ok
  defp report_failure(user, latency_ms, reason) do
    %Error{message: "Ask Glific failed to start a run"}
    |> Glific.log_exception(
      namespace: @appsignal_namespace,
      tags: %{
        organization_id: user.organization_id,
        user_id: user.id,
        latency_ms: latency_ms,
        reason: reason
      }
    )
  end

  @doc """
  Submits feedback (like/dislike) for one of the caller's own turn answers.

  Delegates to `Glific.AI.set_feedback/3`. `{:error, :not_found}` covers both "no such message"
  and "not owned by this user" — `AI.set_feedback/3` already collapses those cases so the error
  can't be used to enumerate other users' messages, and this function keeps that collapse rather
  than un-doing it with a more specific message.
  """
  @spec submit_feedback(map(), User.t()) :: {:ok, map()} | {:error, String.t()}
  def submit_feedback(params, user) do
    rating = Map.get(params, :rating)

    case AI.set_feedback(params.message_id, user.id, rating) do
      {:ok, _message} ->
        record_feedback(rating)
        {:ok, %{success: true}}

      {:error, :not_found} ->
        {:error, "Message not found."}

      {:error, :invalid_rating} ->
        {:error, "Rating must be like or dislike."}

      {:error, %Ecto.Changeset{}} ->
        {:error, "Unable to record feedback."}
    end
  end

  @doc """
  Lists the caller's Ask Glific conversations for the chat history sidebar, most recently
  updated first.
  """
  @spec get_conversations(User.t(), map()) :: {:ok, map()}
  def get_conversations(user, params \\ %{}) do
    limit = Map.get(params, :limit, 20)
    filter = %{user_id: user.id, skill: AskGlificSkill.name()}

    conversations =
      %{filter: filter, opts: %{limit: limit, order: :desc}}
      |> AI.list_conversations()
      |> Enum.map(&to_conversation/1)

    total = AI.count_conversations(%{filter: filter})

    {:ok, %{conversations: conversations, has_more: total > length(conversations), limit: limit}}
  end

  @spec to_conversation(Conversation.t()) :: map()
  defp to_conversation(%Conversation{} = conversation) do
    %{
      id: to_string(conversation.id),
      name: conversation.title,
      status: conversation.status,
      created_at: DateTime.to_unix(conversation.inserted_at),
      updated_at: DateTime.to_unix(conversation.updated_at)
    }
  end

  @doc """
  Fetches a conversation's turn history, oldest-first, scoped to `user` and to the Ask Glific
  skill. Page further back in history with `params.first_id`, the id of the oldest turn already
  loaded (same cursor `Glific.AI.list_turns/2` takes).
  """
  @spec get_messages(String.t(), User.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def get_messages(conversation_id, user, params \\ %{}) do
    limit = Map.get(params, :limit, 20)
    first_id = Map.get(params, :first_id)

    with {:ok, id} <- parse_conversation_id(conversation_id),
         {:ok, conversation} <- AI.fetch_conversation(id, user.id),
         :ok <- ensure_ask_glific_skill(conversation) do
      # Over-fetch by one turn to detect whether older turns remain beyond this page, without
      # a second query — `AI.count_turns/1` can't tell us that on its own once a cursor is in
      # play, since it counts the whole conversation, not what's left beyond `first_id`.
      turns = AI.list_turns(conversation.id, %{limit: limit + 1, first_id: first_id})
      has_more = length(turns) > limit

      {:ok, %{messages: Enum.take(turns, -limit), has_more: has_more, limit: limit}}
    else
      _not_found_or_mismatch -> {:error, "Conversation not found"}
    end
  end

  @spec ensure_ask_glific_skill(Conversation.t()) :: :ok | {:error, :not_found}
  defp ensure_ask_glific_skill(%Conversation{skill: skill}) do
    if skill == AskGlificSkill.name(), do: :ok, else: {:error, :not_found}
  end

  # Tracks request count and latency in AppSignal, mirroring prompt_generator_count/latency.
  @spec record_outcome(String.t(), non_neg_integer()) :: :ok
  defp record_outcome(status, latency_ms) do
    Appsignal.increment_counter("ask_glific_count", 1, %{status: status})
    Appsignal.add_distribution_value("ask_glific_latency", latency_ms, %{status: status})
  end

  # Tracks like/dislike feedback in AppSignal, keyed by the rating a user gave. Reached only
  # after AI.set_feedback/3 returns {:ok, _}, which rejects anything but "like"/"dislike" — the
  # nil rating Dify accepted (to clear a rating) is no longer representable here.
  @spec record_feedback(String.t()) :: :ok
  defp record_feedback(rating) do
    Appsignal.increment_counter("ask_glific_feedback_count", 1, %{rating: rating})
  end
end
