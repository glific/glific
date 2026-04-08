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
    field(:errors, list_of(:input_error))
  end

  input_object :ask_glific_input do
    field(:query, non_null(:string))
    field(:conversation_id, :string)
    field(:page_url, :string)
  end

  object :ask_glific_message do
    field(:id, :string)
    field(:conversation_id, :string)
    field(:query, :string)
    field(:answer, :string)
    field(:created_at, :integer)
  end

  object :askme_bot_messages_result do
    field(:messages, list_of(:ask_glific_message))
    field(:has_more, :boolean)
    field(:limit, :integer)
  end

  object :askme_bot_conversation do
    field(:id, :string)
    field(:name, :string)
    field(:status, :string)
    field(:created_at, :integer)
    field(:updated_at, :integer)
  end

  object :askme_bot_conversations_result do
    field(:conversations, list_of(:askme_bot_conversation))
    field(:has_more, :boolean)
    field(:limit, :integer)
  end

  object :ask_glific_queries do
    field :askme_bot_conversations, :askme_bot_conversations_result do
      arg(:limit, :integer)
      arg(:last_id, :string)
      middleware(Authorize, :staff)
      resolve(&Resolvers.AskGlific.get_conversations/3)
    end

    field :ask_glific_messages, :askme_bot_messages_result do
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
  end
end
