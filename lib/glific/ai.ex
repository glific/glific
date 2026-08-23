defmodule Glific.AI do
  @moduledoc """
  Context for the in-Glific AI agent runtime: `Glific.AI.Conversation` and its
  `Glific.AI.Message` rows.

  The runtime keeps no second, encoded copy of a conversation's transcript — `ai_messages` is
  simultaneously the transcript, the checkpoint, and the audit trail, and `build_context/1` is
  the function the whole design rests on: it rebuilds the model context by reading the rows back
  in order, so a client that refreshes mid-run reconstructs from the same source of truth an Oban
  retry would.

  A conversation's messages can hold data another user in the same organization is not permitted
  to see, so every lookup here is scoped to the requesting user, not just the organization —
  organization scoping alone (the usual `Repo.prepare_query/3` ambient scoping) is not enough.
  """

  import Ecto.Query

  alias Glific.{
    AI.Codec,
    AI.Conversation,
    AI.Message,
    Repo
  }

  @title_max_length 60

  @typedoc """
  One query/answer pair as the `askGlificMessages` GraphQL type expects it: a `user` row paired
  with the `assistant` row that answered it, with every intervening `tool` row dropped.
  """
  @type turn :: %{
          id: String.t(),
          conversation_id: String.t(),
          query: String.t(),
          answer: String.t(),
          created_at: integer(),
          feedback: String.t() | nil
        }

  @doc """
  Creates a conversation.
  """
  @spec create_conversation(map()) :: {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def create_conversation(attrs) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conversation, e.g. to move `active_request_id`/`active_status`/`step_count` as a
  run progresses.
  """
  @spec update_conversation(Conversation.t(), map()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Fetches a conversation by id, scoped to its creator. Raises if not found or not owned by
  `user_id`.
  """
  @spec get_conversation!(pos_integer(), pos_integer()) :: Conversation.t()
  def get_conversation!(id, user_id), do: Repo.get_by!(Conversation, id: id, user_id: user_id)

  @doc """
  Fetches a conversation by id, scoped to its creator.
  """
  @spec fetch_conversation(pos_integer(), pos_integer()) ::
          {:ok, Conversation.t()} | {:error, [String.t()]}
  def fetch_conversation(id, user_id),
    do: Repo.fetch_by(Conversation, %{id: id, user_id: user_id})

  @doc """
  Lists conversations for the chat list. `args.filter.user_id` is required — conversations are
  private to their creator, and this is the guard against listing another user's history.
  """
  @spec list_conversations(map()) :: [Conversation.t()]
  def list_conversations(%{filter: %{user_id: _user_id}} = args) do
    args
    |> Repo.list_filter_query(Conversation, &opts_with_updated_at/2, &filter_with/2)
    |> Repo.all()
  end

  def list_conversations(_args), do: raise_missing_user_id_filter()

  @doc """
  Counts conversations matching a filter. `args.filter.user_id` is required, as in
  `list_conversations/1`.
  """
  @spec count_conversations(map()) :: non_neg_integer()
  def count_conversations(%{filter: %{user_id: _user_id}} = args),
    do: Repo.count_filter(args, Conversation, &filter_with/2)

  def count_conversations(_args), do: raise_missing_user_id_filter()

  @spec raise_missing_user_id_filter() :: no_return()
  defp raise_missing_user_id_filter,
    do:
      raise(ArgumentError,
        message:
          "filter.user_id is required — conversations are private to their creator, " <>
            "and organization scoping alone is not enough"
      )

  # Repo.opts_with_field/3 wraps the sort column in `lower(...)`, which is meant for
  # name/label/body columns and errors on a timestamp — so the chat list sorts with its own
  # helper instead of reusing that one.
  @spec opts_with_updated_at(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp opts_with_updated_at(query, %{order: order}),
    do: order_by(query, [c], {^order, c.updated_at})

  defp opts_with_updated_at(query, _opts), do: query

  @spec filter_with(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:user_id, user_id}, query -> where(query, [c], c.user_id == ^user_id)
      {:status, status}, query -> where(query, [c], c.status == ^status)
      {:skill, skill}, query -> where(query, [c], c.skill == ^skill)
      _unknown, query -> query
    end)
  end

  @doc """
  Lists a conversation's messages ordered by `seq`, for the GraphQL reconnect path
  (`aiMessages`). Always ascending regardless of `args.opts.order`, because seq order is
  transcript order; `args.opts.limit`/`args.opts.offset` still apply.

  Callers must already have verified the caller owns `conversation_id` (e.g. via
  `fetch_conversation/2`) — this function only scopes by `conversation_id`, relying on the
  ambient organization scoping for the rest.
  """
  @spec list_messages(pos_integer(), map()) :: [Message.t()]
  def list_messages(conversation_id, args \\ %{}) do
    args
    |> Map.put(:filter, %{conversation_id: conversation_id})
    |> Repo.list_filter_query(Message, &Repo.opts_with_nil/2, &message_filter_with/2)
    |> order_by([m], asc: m.seq)
    |> Repo.all()
  end

  @doc """
  Counts a conversation's stored messages, used by callers (e.g. `startAiRequest`) to compute
  the next `seq` before appending a seed message. Same ownership caveat as `list_messages/2`:
  scoped only by `conversation_id`, so the caller must already have verified ownership.
  """
  @spec count_messages(pos_integer()) :: non_neg_integer()
  def count_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> Repo.aggregate(:count)
  end

  @spec message_filter_with(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp message_filter_with(query, filter) do
    Enum.reduce(filter, query, fn
      {:conversation_id, conversation_id}, query ->
        where(query, [m], m.conversation_id == ^conversation_id)

      _unknown, query ->
        query
    end)
  end

  @doc """
  Lists a conversation's turns for the `askGlificMessages` chat transcript, oldest-first.

  A turn is a `user` row paired with the *last* `assistant` row that precedes the next `user`
  row — a multi-step run emits an assistant row carrying tool calls (its text is typically
  empty), then `tool` rows, then a final assistant row with the prose answer; only that final
  row is the turn's `answer`, and `tool` rows never surface here. A trailing `user` row with no
  assistant row yet (a run that failed or is still in flight) is dropped rather than returned
  with an empty answer, since the client already renders in-flight state from the
  `askGlificResponse` subscription. `failed` rows are excluded, same as `build_context/1`.

  `args` may carry `:limit` (default 50) and `:first_id` — the id of the oldest turn already
  loaded by the caller, to page further back in history. Turns strictly older than `:first_id`
  are returned, still oldest-first, capped at `:limit`. An unparseable or unknown `:first_id` is
  treated as absent (fetches from the most recent turn) rather than raising.

  Same ownership caveat as `list_messages/2`: scoped only by `conversation_id`, so the caller
  must already have verified ownership (e.g. via `fetch_conversation/2`).
  """
  @spec list_turns(pos_integer(), map()) :: [turn()]
  def list_turns(conversation_id, args \\ %{}) do
    limit = Map.get(args, :limit, 50)
    cursor_seq = resolve_cursor_seq(Map.get(args, :first_id), conversation_id)

    conversation_id
    |> raw_turns(cursor_seq)
    |> take_last(limit)
    |> Enum.map(&to_turn/1)
  end

  @doc """
  Counts a conversation's answered turns, with the same pairing/drop rules as `list_turns/2`.
  """
  @spec count_turns(pos_integer()) :: non_neg_integer()
  def count_turns(conversation_id) do
    conversation_id
    |> raw_turns(nil)
    |> length()
  end

  @spec raw_turns(pos_integer(), integer() | nil) :: [%{user: Message.t(), answer: Message.t()}]
  defp raw_turns(conversation_id, cursor_seq) do
    conversation_id
    |> turn_candidate_messages(cursor_seq)
    |> Repo.all()
    |> pair_turns()
  end

  @spec turn_candidate_messages(pos_integer(), integer() | nil) :: Ecto.Query.t()
  defp turn_candidate_messages(conversation_id, cursor_seq) do
    Message
    |> where(
      [m],
      m.conversation_id == ^conversation_id and m.status == :complete and
        m.role in [:user, :assistant]
    )
    |> maybe_before_seq(cursor_seq)
    |> order_by([m], asc: m.seq)
  end

  @spec maybe_before_seq(Ecto.Query.t(), integer() | nil) :: Ecto.Query.t()
  defp maybe_before_seq(query, nil), do: query
  defp maybe_before_seq(query, seq), do: where(query, [m], m.seq < ^seq)

  @spec resolve_cursor_seq(String.t() | nil, pos_integer()) :: integer() | nil
  defp resolve_cursor_seq(nil, _conversation_id), do: nil

  defp resolve_cursor_seq(first_id, conversation_id) do
    with {id, ""} <- Integer.parse(to_string(first_id)),
         %Message{seq: seq} <- Repo.get_by(Message, id: id, conversation_id: conversation_id) do
      seq
    else
      _not_found_or_unparseable -> nil
    end
  end

  @spec pair_turns([Message.t()]) :: [%{user: Message.t(), answer: Message.t()}]
  defp pair_turns(messages) do
    messages
    |> Enum.reduce([], &accumulate_turn/2)
    |> Enum.reverse()
    |> Enum.filter(& &1.answer)
  end

  @spec accumulate_turn(Message.t(), [%{user: Message.t(), answer: Message.t() | nil}]) ::
          [%{user: Message.t(), answer: Message.t() | nil}]
  defp accumulate_turn(%Message{role: :user} = message, acc),
    do: [%{user: message, answer: nil} | acc]

  defp accumulate_turn(%Message{role: :assistant} = message, [pending | rest]),
    do: [%{pending | answer: message} | rest]

  defp accumulate_turn(%Message{role: :assistant}, [] = acc), do: acc

  @spec take_last([element], non_neg_integer()) :: [element] when element: term()
  defp take_last(list, limit), do: list |> Enum.reverse() |> Enum.take(limit) |> Enum.reverse()

  @spec to_turn(%{user: Message.t(), answer: Message.t()}) :: turn()
  defp to_turn(%{user: user_message, answer: answer_message}) do
    %{
      id: to_string(answer_message.id),
      conversation_id: to_string(user_message.conversation_id),
      query: text_content(user_message),
      answer: text_content(answer_message),
      created_at: DateTime.to_unix(user_message.inserted_at),
      feedback: answer_message.feedback
    }
  end

  # Deliberately duplicated from `Glific.AI.Runtime`'s private `text_content/1` rather than
  # reused: that function is an internal seam of the runtime's step loop, and this context
  # module must not reach into it just to extract display text for the chat transcript.
  @spec text_content(Message.t()) :: String.t()
  defp text_content(%Message{parts: parts}) do
    case Codec.decode(parts) do
      {:ok, %ReqLLM.Message{content: content}} ->
        content
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map_join("", & &1.text)

      {:error, _reason} ->
        ""
    end
  end

  @doc """
  Records a user's like/dislike on a turn's answer.

  `message_id` is the assistant row's id (as returned by `list_turns/2`), arriving as a string
  from GraphQL. `user_id` is not optional: a conversation is private to its creator, so this
  verifies `message_id` belongs to a conversation owned by `user_id` before writing anything,
  and returns `{:error, :not_found}` rather than leaking whether some other user's message
  exists. A malformed `message_id` also returns `{:error, :not_found}` instead of raising.
  """
  @spec set_feedback(String.t(), pos_integer(), String.t()) ::
          {:ok, Message.t()} | {:error, :not_found | :invalid_rating | Ecto.Changeset.t()}
  def set_feedback(message_id, user_id, rating) do
    with {:ok, id} <- parse_message_id(message_id),
         %Message{} = message <- owned_message(id, user_id) do
      message
      |> Message.changeset(%{feedback: rating})
      |> Repo.update()
      |> case do
        {:ok, message} -> {:ok, message}
        {:error, changeset} -> {:error, feedback_error(changeset)}
      end
    else
      nil -> {:error, :not_found}
      {:error, :not_found} = error -> error
    end
  end

  @spec parse_message_id(String.t()) :: {:ok, pos_integer()} | {:error, :not_found}
  defp parse_message_id(message_id) do
    case Integer.parse(to_string(message_id)) do
      {id, ""} when id > 0 -> {:ok, id}
      _malformed -> {:error, :not_found}
    end
  end

  @spec owned_message(pos_integer(), pos_integer()) :: Message.t() | nil
  defp owned_message(id, user_id) do
    Message
    |> join(:inner, [m], c in Conversation, on: c.id == m.conversation_id)
    |> where([m, c], m.id == ^id and c.user_id == ^user_id)
    |> Repo.one()
  end

  @spec feedback_error(Ecto.Changeset.t()) :: :invalid_rating | Ecto.Changeset.t()
  defp feedback_error(changeset) do
    if Keyword.has_key?(changeset.errors, :feedback), do: :invalid_rating, else: changeset
  end

  @doc """
  Derives a display title for a conversation from its first user message: truncated to about
  #{@title_max_length} characters on a word boundary, with a trailing ellipsis when cut. Short
  input is returned untouched.

  Deliberately not model-generated. The Dify implementation this replaces
  (`Glific.AskGlific.generate_conversation_name/2`) calls a model in a second round trip before
  the answer can be published — that is a latency bug being removed here, not a feature being
  preserved.
  """
  @spec derive_title(String.t()) :: String.t()
  def derive_title(text) do
    trimmed = text |> to_string() |> String.trim()

    if String.length(trimmed) <= @title_max_length do
      trimmed
    else
      trimmed
      |> String.slice(0, @title_max_length)
      |> truncate_at_word_boundary()
      |> Kernel.<>("…")
    end
  end

  @spec truncate_at_word_boundary(String.t()) :: String.t()
  defp truncate_at_word_boundary(slice) do
    case String.split(slice, " ") do
      [_single_word] -> slice
      words -> words |> Enum.slice(0..-2//1) |> Enum.join(" ")
    end
  end

  @doc """
  Appends one message row at `attrs.seq`.

  Inserts with `on_conflict: :nothing` against the unique `(conversation_id, seq)` index, so a
  retried step is a no-op rather than a duplicate. The caller can tell the two cases apart:
  `{:ok, :inserted}` for a first write, `{:ok, :already_present}` for a replay.
  """
  @spec append_message(Conversation.t(), map()) ::
          {:ok, :inserted} | {:ok, :already_present} | {:error, Ecto.Changeset.t()}
  def append_message(%Conversation{} = conversation, attrs) do
    attrs =
      attrs
      |> Map.put(:conversation_id, conversation.id)
      |> Map.put(:organization_id, conversation.organization_id)

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:conversation_id, :seq])
    |> case do
      {:ok, %Message{id: nil}} -> {:ok, :already_present}
      {:ok, %Message{}} -> {:ok, :inserted}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Rebuilds the model context for a conversation from its stored messages: every `complete` row,
  ordered by `seq`, decoded back through `Glific.AI.Codec`. `failed` rows are excluded, matching
  the codec/table contract in `Glific.AI.Message`.

  This is the function the two-table design rests on — nothing else reconstructs history.
  """
  @spec build_context(pos_integer()) :: {:ok, ReqLLM.Context.t()} | {:error, term()}
  def build_context(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id and m.status == :complete)
    |> order_by([m], asc: m.seq)
    |> Repo.all()
    |> decode_messages()
  end

  @spec decode_messages([Message.t()]) :: {:ok, ReqLLM.Context.t()} | {:error, term()}
  defp decode_messages(messages) do
    messages
    |> Enum.reduce_while({:ok, []}, fn message, {:ok, acc} ->
      case Codec.decode(message.parts) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:error, reason} -> {:halt, {:error, {message.id, reason}}}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, ReqLLM.Context.new(Enum.reverse(decoded))}
      {:error, _reason} = error -> error
    end
  end
end
