defmodule Glific.AskGlific.Bridge do
  @moduledoc """
  Temporary compatibility layer translating the AI agent runtime's `ai_request_event`
  publications into the legacy `ask_glific_response` subscription the Ask Glific frontend still
  listens on.

  Phase 3 of the Ask Glific migration moves the skill off Dify and onto
  `Glific.AI.Skills.AskGlific` / `Glific.AI.StepWorker` without touching the frontend at all —
  the frontend keeps subscribing to `ask_glific_response` exactly as it always has, and this
  module is the adapter that makes that possible. `Glific.AI.Publisher.publish/4` calls into
  this module, alongside its own generic `ai_request_event` publish, for every conversation
  whose `skill` is `"ask_glific"`.

  This is temporary. Its exit condition is the Ask Glific frontend migrating to subscribe on
  `ai_request_event` directly (the vocabulary every other AI skill already uses) — once that
  ships, this module, its call site in `Glific.AI.Publisher`, and the `ask_glific_response`
  subscription in `GlificWeb.Schema.AskGlificTypes` can all be deleted together.
  """

  import Ecto.Query

  alias Glific.AI.Codec
  alias Glific.AI.Conversation
  alias Glific.AI.Message
  alias Glific.AI.Publisher
  alias Glific.Repo

  @doc """
  Translates one runtime event into the legacy `ask_glific_response` shape and publishes it, or
  does nothing for an event the legacy frontend has no vocabulary for (`:queued`, `:delta`,
  `:message`, `:proposal`).
  """
  @spec publish(Conversation.t(), Publisher.event(), String.t() | nil, map()) :: :ok
  def publish(%Conversation{} = conversation, :final, request_id, _fields) do
    case newest_answer(conversation.id) do
      %Message{} = message ->
        publish_response(conversation, final_envelope(conversation, message, request_id))

      nil ->
        :ok
    end
  end

  def publish(%Conversation{} = conversation, :error, request_id, fields),
    do: publish_response(conversation, error_envelope(conversation, request_id, fields))

  def publish(%Conversation{}, _event, _request_id, _fields), do: :ok

  @doc false
  @spec final_envelope(Conversation.t(), Message.t(), String.t() | nil) :: map()
  def final_envelope(%Conversation{} = conversation, %Message{} = message, request_id) do
    %{
      answer: answer_text(message),
      conversation_id: to_string(conversation.id),
      conversation_name: conversation.title,
      message_id: to_string(message.id),
      request_id: request_id,
      errors: []
    }
  end

  @doc false
  @spec error_envelope(Conversation.t(), String.t() | nil, map()) :: map()
  def error_envelope(%Conversation{} = conversation, request_id, fields) do
    %{
      answer: nil,
      conversation_id: to_string(conversation.id),
      conversation_name: conversation.title,
      message_id: nil,
      request_id: request_id,
      errors: Map.get(fields, :errors, [])
    }
  end

  @spec publish_response(Conversation.t(), map()) :: :ok
  defp publish_response(conversation, payload) do
    Absinthe.Subscription.publish(
      GlificWeb.Endpoint,
      payload,
      ask_glific_response: Publisher.topic(conversation)
    )

    :ok
  end

  # The assistant row `askGlificFeedback` needs `message_id` for — the final, prose-bearing
  # answer of the run, not any intermediate assistant row carrying tool calls.
  @spec newest_answer(pos_integer()) :: Message.t() | nil
  defp newest_answer(conversation_id) do
    Message
    |> where(
      [m],
      m.conversation_id == ^conversation_id and m.role == :assistant and m.status == :complete
    )
    |> order_by([m], desc: m.seq)
    |> limit(1)
    |> Repo.one()
  end

  # Deliberately duplicated from `Glific.AI`'s private `text_content/1` rather than reused, for
  # the same reason that module's own duplicate exists: this is a display-text extraction for a
  # different consumer, not an internal seam of the runtime's step loop.
  @spec answer_text(Message.t()) :: String.t()
  defp answer_text(%Message{parts: parts}) do
    case Codec.decode(parts) do
      {:ok, %ReqLLM.Message{content: content}} ->
        content
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map_join("", & &1.text)

      {:error, _reason} ->
        ""
    end
  end
end
