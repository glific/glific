defmodule GlificWeb.Schema.AssistantChatTypes do
  @moduledoc """
  GraphQL surface for sending a chat message to an assistant's live Kaapi config
  version (the "Try It Out" sandbox) and receiving the async reply over a
  subscription. Dispatch (`send_assistant_message`) just queues the job on Kaapi and
  returns immediately; the actual answer arrives later via `llm_call_response` once
  Kaapi calls back.
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  @desc "Result of dispatching (or the async reply to) an assistant chat message.
  `job_id` is only present on the dispatch ack; `answer` is only present on the
  subscription payload delivered once Kaapi's callback arrives."
  object :llm_call_result do
    field(:job_id, :string)
    field(:request_id, :string)
    field(:conversation_id, :string)
    field(:answer, :string)
    field(:errors, list_of(:input_error))
  end

  input_object :llm_call_input do
    field(:assistant_id, non_null(:id))
    field(:message, non_null(:string))
    field(:conversation_id, :string)
  end

  object :assistant_chat_mutations do
    @desc "Send a chat message to an assistant's live config version via Kaapi. Returns
    a job_id immediately; the reply is delivered over the llm_call_response subscription."
    field :send_assistant_message, :llm_call_result do
      arg(:input, non_null(:llm_call_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.AssistantChat.send_message/3)
    end
  end

  object :assistant_chat_subscriptions do
    @desc "Delivers the async reply to a send_assistant_message dispatch."
    field :llm_call_response, :llm_call_result do
      arg(:organization_id, non_null(:id))

      config(fn args, %{context: %{current_user: user}} ->
        if args.organization_id == Integer.to_string(user.organization_id) do
          {:ok, topic: "#{user.organization_id}:#{user.id}"}
        else
          {:error, "Auth Credentials mismatch"}
        end
      end)
    end
  end
end
