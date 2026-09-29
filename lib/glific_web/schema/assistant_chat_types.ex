defmodule GlificWeb.Schema.AssistantChatTypes do
  @moduledoc """
  GraphQL surface for sending a chat message to a selected (default: live) Kaapi config
  version of an assistant (the "Try It Out" sandbox) and receiving the async reply over a
  subscription. Dispatch (`send_assistant_message`) just queues the job on Kaapi and
  returns immediately; the actual answer arrives later via `assistant_chat_response`
  once Kaapi calls back.
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  @desc "Result of dispatching (or the async reply to) an assistant chat message.
  `job_id` is only present on the dispatch ack; `answer` is only present on the
  subscription payload delivered once Kaapi's callback arrives."
  object :assistant_chat_result do
    field(:job_id, :string)
    field(:request_id, :string)
    field(:conversation_id, :string)
    field(:answer, :string)
    field(:errors, list_of(:input_error))
  end

  input_object :assistant_chat_input do
    field(:assistant_id, non_null(:id))
    field(:message, non_null(:string))
    field(:conversation_id, :string)

    @desc "Config version to chat with. Defaults to the assistant's live version."
    field(:config_version_id, :id)
  end

  object :assistant_chat_mutations do
    @desc "Send a chat message to the selected (default: live) config version of an assistant
    via Kaapi. Returns a job_id immediately; the reply is delivered over the
    assistant_chat_response subscription."
    field :send_assistant_message, :assistant_chat_result do
      arg(:input, non_null(:assistant_chat_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.AssistantChat.send_message/3)
    end
  end

  object :assistant_chat_subscriptions do
    @desc "Delivers the async reply to a send_assistant_message dispatch."
    field :assistant_chat_response, :assistant_chat_result do
      config(fn _args, %{context: %{current_user: user}} ->
        {:ok, topic: "#{user.organization_id}:#{user.id}"}
      end)
    end
  end
end
