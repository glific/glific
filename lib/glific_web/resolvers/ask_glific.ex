defmodule GlificWeb.Resolvers.AskGlific do
  @moduledoc """
  AskGlific Resolver which sits between the GraphQL schema and Glific AskGlific module.
  """

  alias Glific.AskGlific

  @doc """
  Ask the AskGlific bot a question. Triggers async Dify call and
  publishes the response via Absinthe subscription.
  """
  @spec ask(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def ask(_, %{input: params}, %{context: %{current_user: user}}) do
    Task.start(fn ->
      Glific.Repo.put_process_state(user.organization_id)

      topic = "#{user.organization_id}:#{user.id}"

      case AskGlific.ask(params, user) do
        {:ok, result} ->
          Absinthe.Subscription.publish(
            GlificWeb.Endpoint,
            result,
            [{:ask_glific_response, topic}]
          )

        {:error, reason} ->
          Absinthe.Subscription.publish(
            GlificWeb.Endpoint,
            %{answer: nil, conversation_id: nil, errors: [%{key: "error", message: reason}]},
            [{:ask_glific_response, topic}]
          )
      end
    end)

    {:ok, %{answer: nil, conversation_id: nil}}
  end

  @doc """
  Fetches conversations from Dify for the current user.
  """
  @spec get_conversations(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def get_conversations(_, args, %{context: %{current_user: user}}) do
    AskGlific.get_conversations(user, args)
  end

  @doc """
  Fetch message history for a conversation from Dify.
  """
  @spec messages(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def messages(_, %{conversation_id: conversation_id} = args, %{context: %{current_user: user}}) do
    AskGlific.get_messages(conversation_id, user, args)
  end

  @doc """
  Submit feedback for a Dify message.
  """
  @spec submit_feedback(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def submit_feedback(_, %{input: params}, %{context: %{current_user: user}}) do
    AskGlific.submit_feedback(params, user)
  end
end
