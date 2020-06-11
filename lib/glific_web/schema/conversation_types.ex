defmodule GlificWeb.Schema.ConversationTypes do
  @moduledoc """
  GraphQL Representation of Glific's Conversation Data. This is virtual and pulled
  together from multiple pieces by Glific Core
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  object :conversation do
    field :contact, :contact
    field :messages, list_of(:message)
  end

  @desc "Filtering options for conversations"
  input_object :conversation_filter do
    @desc "Match one contact ID"
    field :id, :id

    @desc "Match multiple contact ids"
    field :ids, list_of(:id)

    @desc "Include conversations with these tags"
    field :include_tags, list_of(:id)

    @desc "Exclude conversations with these tags"
    field :exclude_tags, list_of(:id)
  end

  object :conversation_queries do
    @desc "get the conversations"
    field :conversations, list_of(:conversation) do
      arg(:number_of_conversations, non_null(:integer))
      arg(:size_of_conversations, non_null(:integer))
      arg(:filter, :conversation_filter)
      resolve(&Resolvers.Conversations.conversations/3)
    end
  end
end
