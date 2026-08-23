defmodule GlificWeb.Resolvers.AskGlific do
  @moduledoc """
  Resolver for the Ask Glific GraphQL surface: dispatching a question (`askGlific`), reading
  back conversation/message history (`askGlificConversations`/`askGlificMessages`), and
  recording feedback on an answer (`askGlificFeedback`).

  `ask/3` only validates and acks — the actual model call runs asynchronously on
  `Glific.AI.StepWorker`, and the answer is published later on the `ask_glific_response`
  subscription (bridged from the AI runtime's `ai_request_event` topic by
  `Glific.AskGlific.Bridge`). Every atom `Glific.AskGlific.ask/2` can return is mapped here to a
  generic, stable public message — none of `Glific.AskGlific`'s internal reasons leak past this
  boundary.
  """

  alias Glific.AskGlific

  @doc """
  Starts (or continues) an Ask Glific run and acks synchronously. `answer` is always `nil` on
  this ack; the real answer arrives on the `ask_glific_response` subscription.
  """
  @spec ask(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) :: {:ok, map()}
  def ask(_, %{input: params}, %{context: %{current_user: user}}) do
    case AskGlific.ask(params, user) do
      {:ok, ack} -> {:ok, ack}
      {:error, reason} -> {:ok, error_ack(params, reason)}
    end
  end

  @doc """
  Lists the caller's Ask Glific conversations for the chat history sidebar.
  """
  @spec get_conversations(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, map()}
  def get_conversations(_, args, %{context: %{current_user: user}}),
    do: AskGlific.get_conversations(user, args)

  @doc """
  Fetches a conversation's turn history, scoped to the caller.
  """
  @spec messages(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def messages(_, %{conversation_id: conversation_id} = args, %{context: %{current_user: user}}),
    do: AskGlific.get_messages(conversation_id, user, args)

  @doc """
  Submits feedback (like/dislike) for one of the caller's own turn answers.
  """
  @spec submit_feedback(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def submit_feedback(_, %{input: params}, %{context: %{current_user: user}}),
    do: AskGlific.submit_feedback(params, user)

  @spec error_ack(map(), atom() | String.t() | Ecto.Changeset.t()) :: map()
  defp error_ack(params, reason) do
    %{
      answer: nil,
      conversation_id: nil,
      conversation_name: nil,
      message_id: nil,
      request_id: Map.get(params, :request_id),
      errors: [%{key: "ask_glific", message: error_message(reason)}]
    }
  end

  @spec error_message(atom() | String.t() | Ecto.Changeset.t()) :: String.t()
  defp error_message(:feature_disabled), do: "Ask Glific is not enabled for your organization."
  defp error_message(:forbidden), do: "You do not have permission to use Ask Glific."
  defp error_message(:rate_limited), do: "Too many requests. Please try again in a minute."

  defp error_message(:busy),
    do: "A request is already in progress for this conversation."

  defp error_message(:skill_mismatch),
    do: "This conversation belongs to a different skill."

  defp error_message(:not_found), do: "Conversation not found."
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(_reason), do: "Something went wrong. Please try again."
end
