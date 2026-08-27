defmodule Glific.AI.AskGlific do
  @moduledoc """
  Glific AI behind the existing Ask Glific interface.

  `Glific.AskGlific` routes here instead of to Dify when the `glific_ai_enabled`
  flag is on for an organisation. The return shapes are identical, so the chat
  window, its history and its feedback control keep working with no frontend
  change — the only difference is where the answer comes from and where the
  conversation is stored.

  Two differences from the Dify path worth knowing:

    * conversation ids are Glific's own integer ids rendered as strings, not
      Dify UUIDs. Existing Dify conversations are not migrated; a user who is
      switched over starts a fresh history.
    * the current user is set from the person who asked, so reads run under
      their permissions. The Dify path calls `Repo.put_process_state/1`, which
      substitutes the organisation's root user.
  """

  import Ecto.Query

  alias Glific.{
    AI,
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.Models,
    AI.Provider,
    AI.Request,
    AI.Usage,
    Repo
  }

  @skill "knowledge"
  @name_length 60
  @default_limit 20

  @doc """
  Answers a question, recording the exchange against a conversation.
  """
  @spec ask(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def ask(params, user) do
    # Reads must run as the person asking, not as the organisation's root user.
    Repo.put_current_user(user)

    query = params |> Map.get(:query) |> to_string() |> String.trim()

    if query == "" do
      {:error, "Query is required"}
    else
      with {:ok, conversation, new?} <- conversation(Map.get(params, :conversation_id, ""), user) do
        answer(conversation, query, new?, user)
      end
    end
  end

  @doc """
  The user's Glific AI conversations, most recent first.
  """
  @spec get_conversations(map(), map()) :: {:ok, map()}
  def get_conversations(user, params \\ %{}) do
    limit = Map.get(params, :limit) || @default_limit

    conversations =
      Conversation
      |> where([c], c.user_id == ^user.id)
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

  Ordered by `(request_id, step)` rather than by timestamp: two requests in
  one thread can be in flight at once, and timestamps can tie.
  """
  @spec get_messages(String.t(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def get_messages(conversation_id, user, params \\ %{}) do
    limit = Map.get(params, :limit) || @default_limit

    case owned_conversation(conversation_id, user) do
      nil ->
        {:error, "Conversation not found"}

      conversation ->
        events =
          conversation
          |> events_query()
          |> Repo.all()

        {:ok,
         %{
           messages: events |> exchanges(conversation) |> Enum.take(limit),
           has_more: false,
           limit: limit
         }}
    end
  end

  @doc """
  Records a rating against an answer.

  Feedback is kept in the event's `data`, so it needs no column of its own until
  we know what we want to do with it.
  """
  @spec submit_feedback(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def submit_feedback(params, user) do
    with {id, ""} <- Integer.parse(to_string(Map.get(params, :message_id, ""))),
         %Event{} = event <- owned_event(id, user) do
      feedback =
        %{"rating" => Map.get(params, :rating), "content" => Map.get(params, :content)}
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      event
      |> Event.changeset(%{data: Map.put(event.data, "feedback", feedback)})
      |> Repo.update()
      |> case do
        {:ok, _} -> {:ok, %{success: true}}
        {:error, _} -> {:error, "Could not record feedback"}
      end
    else
      _ -> {:error, "Message not found"}
    end
  end

  # ── asking ───────────────────────────────────────────────────────────────

  @spec answer(Conversation.t(), String.t(), boolean(), map()) ::
          {:ok, map()} | {:error, String.t()}
  defp answer(conversation, query, new?, user) do
    request = start_request(conversation, user)
    history = conversation |> events_query() |> Repo.all() |> Enum.map(&to_message/1)

    {:ok, _} = append(request, 1, :user, query)

    case AI.generate(user.organization_id, history ++ [Message.user(query)]) do
      {:ok, %Message{content: content}, %Usage{} = usage} ->
        {:ok, event} = append(request, 2, :assistant, content)
        finish(request, :succeeded, usage)
        {:ok, result(conversation, content, event, new?, query)}

      {:error, reason} ->
        fail(request, reason)
        {:error, describe(reason)}
    end
  end

  @spec start_request(Conversation.t(), map()) :: Request.t()
  defp start_request(conversation, user) do
    %Request{}
    |> Request.changeset(%{
      conversation_id: conversation.id,
      user_id: user.id,
      organization_id: conversation.organization_id,
      skill: @skill,
      model: Models.spec(),
      status: :running
    })
    |> Repo.insert!()
  end

  @spec append(Request.t(), non_neg_integer(), atom(), String.t() | nil) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  defp append(request, step, type, content) do
    %Event{}
    |> Event.changeset(%{
      request_id: request.id,
      conversation_id: request.conversation_id,
      organization_id: request.organization_id,
      step: step,
      type: type,
      content: content
    })
    |> Repo.insert()
  end

  @spec finish(Request.t(), atom(), Usage.t()) :: Request.t()
  defp finish(request, status, usage) do
    request
    |> Request.changeset(%{
      status: status,
      input_tokens: usage.input_tokens,
      output_tokens: usage.output_tokens,
      cost: usage.cost
    })
    |> Repo.update!()
  end

  @spec fail(Request.t(), term()) :: Request.t()
  defp fail(request, reason) do
    request
    |> Request.changeset(%{status: :failed, error: describe(reason)})
    |> Repo.update!()
  end

  # ── conversations ────────────────────────────────────────────────────────

  @spec conversation(String.t() | nil, map()) ::
          {:ok, Conversation.t(), boolean()} | {:error, String.t()}
  defp conversation(id, user) when id in [nil, ""] do
    conversation =
      %Conversation{}
      |> Conversation.changeset(%{user_id: user.id, organization_id: user.organization_id})
      |> Repo.insert!()

    {:ok, conversation, true}
  end

  defp conversation(id, user) do
    case owned_conversation(id, user) do
      nil -> {:error, "Conversation not found"}
      conversation -> {:ok, conversation, false}
    end
  end

  @spec owned_conversation(String.t(), map()) :: Conversation.t() | nil
  defp owned_conversation(id, user) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> Repo.get_by(Conversation, id: id, user_id: user.id)
      _ -> nil
    end
  end

  @spec owned_event(non_neg_integer(), map()) :: Event.t() | nil
  defp owned_event(id, user) do
    Event
    |> join(:inner, [e], c in Conversation, on: c.id == e.conversation_id)
    |> where([e, c], e.id == ^id and c.user_id == ^user.id and e.type == :assistant)
    |> Repo.one()
  end

  @spec events_query(Conversation.t()) :: Ecto.Query.t()
  defp events_query(conversation) do
    Event
    |> where([e], e.conversation_id == ^conversation.id)
    |> where([e], e.type in [:user, :assistant])
    |> order_by([e], asc: e.request_id, asc: e.step)
  end

  # ── rendering, to the shapes the existing GraphQL types expect ───────────

  @spec result(Conversation.t(), String.t() | nil, Event.t(), boolean(), String.t()) :: map()
  defp result(conversation, content, event, new?, query) do
    %{
      answer: content,
      conversation_id: to_string(conversation.id),
      conversation_name: if(new?, do: name_from(query, conversation)),
      message_id: to_string(event.id)
    }
  end

  @spec name_from(String.t(), Conversation.t()) :: String.t()
  defp name_from(query, conversation) do
    name = String.slice(query, 0, @name_length)
    conversation |> Conversation.changeset(%{title: name}) |> Repo.update!()
    name
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

  # The interface shows one row per exchange, so a user event and the assistant
  # event that answered it are folded together.
  @spec exchanges([Event.t()], Conversation.t()) :: [map()]
  defp exchanges(events, conversation) do
    events
    |> Enum.group_by(& &1.request_id)
    |> Enum.sort_by(fn {request_id, _} -> request_id end)
    |> Enum.map(fn {_request_id, grouped} -> exchange(grouped, conversation) end)
  end

  @spec exchange([Event.t()], Conversation.t()) :: map()
  defp exchange(events, conversation) do
    asked = Enum.find(events, &(&1.type == :user))
    answered = Enum.find(events, &(&1.type == :assistant))

    %{
      id: to_string((answered || asked).id),
      conversation_id: to_string(conversation.id),
      query: asked && asked.content,
      answer: answered && answered.content,
      created_at: unix((asked || answered).inserted_at),
      feedback: answered && get_in(answered.data, ["feedback", "rating"])
    }
  end

  @spec to_message(Event.t()) :: Message.t()
  defp to_message(%Event{type: :assistant, content: content}),
    do: Message.assistant(content || "")

  defp to_message(%Event{content: content}), do: Message.user(content || "")

  @spec unix(DateTime.t() | nil) :: integer() | nil
  defp unix(nil), do: nil
  defp unix(datetime), do: DateTime.to_unix(datetime)

  @spec describe(:disabled | Provider.failure()) :: String.t()
  defp describe(:disabled), do: "Glific AI is not enabled"
  defp describe({_kind, message}), do: message
end
