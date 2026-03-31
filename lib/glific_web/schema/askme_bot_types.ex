defmodule GlificWeb.Schema.AskmeBotTypes do
  @moduledoc """
  GraphQL Representation of AskMe Bot DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :askme_bot_result do
    field(:answer, :string)
    field(:conversation_id, :string)
    field(:errors, list_of(:input_error))
  end

  input_object :askme_bot_input do
    @desc "The question to ask"
    field(:query, non_null(:string))

    @desc "Dify conversation ID for follow-up questions (empty string for new conversation)"
    field(:conversation_id, :string)
  end

  object :askme_bot_mutations do
    field :askme_bot, :askme_bot_result do
      arg(:input, non_null(:askme_bot_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.AskmeBot.ask/3)
    end
  end
end
