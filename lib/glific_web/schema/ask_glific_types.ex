defmodule GlificWeb.Schema.AskGlificTypes do
  @moduledoc """
  GraphQL Representation of AskGlific DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :ask_glific_result do
    field(:answer, :string)
    field(:conversation_id, :string)
    field(:conversation_name, :string)
    field(:message_id, :string)
    field(:request_id, :string)
    field(:errors, list_of(:input_error))
  end

  object :ask_glific_feedback_result do
    field(:success, :boolean)
  end

  input_object :ask_glific_feedback_input do
    field(:message_id, non_null(:string))
    field(:rating, :string)
    field(:content, :string)
  end

  input_object :ask_glific_input do
    field(:query, non_null(:string))
    field(:conversation_id, :string)
    field(:page_url, :string)
    field(:request_id, :string)
  end

  object :ask_glific_message do
    field(:id, :string)
    field(:conversation_id, :string)
    field(:query, :string)
    field(:answer, :string)
    field(:created_at, :integer)
    field(:feedback, :string)
  end

  object :ask_glific_messages_result do
    field(:messages, list_of(:ask_glific_message))
    field(:has_more, :boolean)
    field(:limit, :integer)
  end

  object :ask_glific_conversation do
    field(:id, :string)
    field(:name, :string)
    field(:status, :string)
    field(:created_at, :integer)
    field(:updated_at, :integer)
  end

  object :ask_glific_conversations_result do
    field(:conversations, list_of(:ask_glific_conversation))
    field(:has_more, :boolean)
    field(:limit, :integer)
  end

  object :ask_glific_queries do
    field :ask_glific_conversations, :ask_glific_conversations_result do
      arg(:limit, :integer)
      arg(:last_id, :string)
      middleware(Authorize, :staff)
      resolve(&Resolvers.AskGlific.get_conversations/3)
    end

    field :ask_glific_messages, :ask_glific_messages_result do
      arg(:conversation_id, non_null(:string))
      arg(:limit, :integer)
      arg(:first_id, :string)
      middleware(Authorize, :staff)
      resolve(&Resolvers.AskGlific.messages/3)
    end
  end

  object :ask_glific_mutations do
    field :ask_glific, :ask_glific_result do
      arg(:input, non_null(:ask_glific_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.AskGlific.ask/3)
    end

    field :ask_glific_feedback, :ask_glific_feedback_result do
      arg(:input, non_null(:ask_glific_feedback_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.AskGlific.submit_feedback/3)
    end
  end

  object :ask_glific_subscriptions do
    field :ask_glific_response, :ask_glific_result do
      arg(:organization_id, non_null(:id))

      config(fn args, %{context: %{current_user: user}} ->
        if args.organization_id == Integer.to_string(user.organization_id) do
          {:ok, [topic: "#{user.organization_id}:#{user.id}"]}
        else
          {:error, "Auth Credentials mismatch"}
        end
      end)
    end
  end
end
