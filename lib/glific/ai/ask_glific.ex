defmodule Glific.AI.AskGlific do
  @moduledoc """
  Answers Ask Glific questions with Glific AI instead of Dify.

  `Glific.AskGlific` routes here when the `glific_ai_enabled` flag is on for an
  organisation. The return shapes match the Dify path, so the chat window, its
  history and its feedback control work unchanged.

  Two differences:

    * conversation ids are Glific ids rendered as strings, not Dify UUIDs.
      Existing Dify conversations are not migrated, so a user switched over
      starts with an empty history.
    * the current user is set from whoever asked, so reads run under their
      permissions rather than the organisation's root user.
  """

  import Ecto.Query

  alias Glific.{
    AI.Agent,
    AI.Conversation,
    AI.Event,
    AI.Instrumentation,
    AI.Message,
    Repo
  }

  @name_length 60
  @default_limit 20

  @doc """
  Answers a question, recording the exchange against a conversation.
  """
  @spec ask(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def ask(params, user) do
    Repo.put_current_user(user)

    query = params |> Map.get(:query) |> to_string() |> String.trim()

    if query == "" do
      {:error, "Query is required"}
    else
      with {:ok, conversation, new?} <-
             conversation(Map.get(params, :conversation_id, ""), user, query) do
        answer(conversation, new?, user, query, Map.get(params, :skill))
      end
    end
  end

  @doc """
  The user's chat threads, most recent first.

  Only `:chat` threads: a skill run on its own gets a thread of its own, and
  those are not part of anything the person typed.
  """
  @spec get_conversations(map(), map()) :: {:ok, map()}
  def get_conversations(user, params \\ %{}) do
    limit = Map.get(params, :limit) || @default_limit

    conversations =
      Conversation
      |> where([c], c.user_id == ^user.id and c.kind == :chat)
      |> order_by([c], desc: c.updated_at)
      |> limit(^(limit + 1))
      |> Repo.all()

    {:ok,
     %{
       conversations: conversations |> Enum.take(limit) |> Enum.map(&render_conversation/1),
       has_more: length(conversations) > limit,
       limit: limit
     }}
  end

  @doc """
  The exchanges in one conversation, oldest first.

  Ordered by `(message_id, step)` rather than by timestamp: two questions in
  one thread can be in flight at once, and timestamps can tie.
  """
  @spec get_messages(String.t(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def get_messages(conversation_id, user, params \\ %{}) do
    limit = Map.get(params, :limit) || @default_limit

    case owned_conversation(conversation_id, user) do
      nil ->
        {:error, "Conversation not found"}

      conversation ->
        messages =
          Event
          |> where([e], e.conversation_id == ^conversation.id)
          |> where([e], e.type in [:user, :assistant])
          |> order_by([e], asc: e.message_id, asc: e.step)
          |> Repo.all()
          |> Enum.chunk_by(& &1.message_id)
          |> Enum.map(&exchange/1)
          |> Enum.take(limit)

        {:ok, %{messages: messages, has_more: false, limit: limit}}
    end
  end

  @doc """
  Records a rating against an answer.

  The rating is stored in the answer event's `data` rather than in a column of
  its own.
  """
  @spec submit_feedback(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def submit_feedback(params, user) do
    with {:ok, id} when is_integer(id) <-
           Glific.parse_maybe_integer(Map.get(params, :message_id, "")),
         %Event{} = event <- owned_event(id, user) do
      feedback =
        %{"rating" => Map.get(params, :rating), "content" => Map.get(params, :content)}
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      event
      |> Event.changeset(%{data: Map.put(event.data, "feedback", feedback)})
      |> Repo.update()
      |> case do
        {:ok, _} ->
          Instrumentation.feedback(Map.get(params, :rating))
          {:ok, %{success: true}}

        {:error, _} ->
          {:error, "Could not record feedback"}
      end
    else
      _ -> {:error, "Message not found"}
    end
  end

  @spec answer(Conversation.t(), boolean(), map(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, String.t()}
  defp answer(conversation, new?, user, query, skill) do
    message = start_message(conversation, user, query)

    case Agent.run(message, user, skill: skill) do
      {:ok, content, meta} -> {:ok, result(conversation, content, meta, new?)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_message(Conversation.t(), map(), String.t()) :: Message.t()
  defp start_message(conversation, user, query) do
    message =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        user_id: user.id,
        organization_id: conversation.organization_id,
        status: :running
      })
      |> Repo.insert!()

    %Event{}
    |> Event.changeset(%{
      message_id: message.id,
      conversation_id: message.conversation_id,
      organization_id: message.organization_id,
      step: 1,
      type: :user,
      content: query
    })
    |> Repo.insert!()

    record_activity(conversation)

    message
  end

  @spec record_activity(Conversation.t()) :: :ok
  defp record_activity(conversation) do
    Conversation
    |> where([c], c.id == ^conversation.id)
    |> Repo.update_all(set: [updated_at: DateTime.utc_now()])

    :ok
  end

  @spec conversation(String.t() | nil, map(), String.t()) ::
          {:ok, Conversation.t(), boolean()} | {:error, String.t()}
  defp conversation(id, user, query) when id in [nil, ""] do
    conversation =
      %Conversation{}
      |> Conversation.changeset(%{
        user_id: user.id,
        organization_id: user.organization_id,
        title: String.slice(query, 0, @name_length)
      })
      |> Repo.insert!()

    {:ok, conversation, true}
  end

  defp conversation(id, user, _query) do
    case owned_conversation(id, user) do
      nil -> {:error, "Conversation not found"}
      conversation -> {:ok, conversation, false}
    end
  end

  @spec owned_conversation(String.t(), map()) :: Conversation.t() | nil
  defp owned_conversation(id, user) do
    case Glific.parse_maybe_integer(id) do
      {:ok, id} -> Repo.get_by(Conversation, id: id, user_id: user.id, kind: :chat)
      :error -> nil
    end
  end

  @spec owned_event(non_neg_integer(), map()) :: Event.t() | nil
  defp owned_event(id, user) do
    Event
    |> join(:inner, [e], c in Conversation, on: c.id == e.conversation_id)
    |> where([e, c], e.id == ^id and c.user_id == ^user.id and e.type == :assistant)
    |> Repo.one()
  end

  @spec result(Conversation.t(), String.t() | nil, Agent.meta(), boolean()) :: map()
  defp result(conversation, content, meta, new?) do
    %{
      answer: content,
      conversation_id: to_string(conversation.id),
      conversation_name: if(new?, do: conversation.title),
      message_id: meta.answer_event_id && to_string(meta.answer_event_id),
      skill: meta.skill
    }
  end

  @spec render_conversation(Conversation.t()) :: map()
  defp render_conversation(conversation) do
    %{
      id: to_string(conversation.id),
      name: conversation.title,
      status: "normal",
      created_at: unix(conversation.inserted_at),
      updated_at: unix(conversation.updated_at)
    }
  end

  @spec exchange([Event.t()]) :: map()
  defp exchange(events) do
    asked = Enum.find(events, &(&1.type == :user))
    answered = Enum.find(events, &(&1.type == :assistant))

    %{
      id: to_string((answered || asked).id),
      conversation_id: to_string((asked || answered).conversation_id),
      query: asked && asked.content,
      answer: answered && answered.content,
      created_at: unix((asked || answered).inserted_at),
      feedback: answered && get_in(answered.data, ["feedback", "rating"])
    }
  end

  @spec unix(DateTime.t() | nil) :: integer() | nil
  defp unix(nil), do: nil
  defp unix(datetime), do: DateTime.to_unix(datetime)
end
