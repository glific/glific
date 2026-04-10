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

  object :ask_glific_queries do
    field :ask_glific_messages, list_of(:ask_glific_message) do
      arg(:conversation_id, non_null(:string))
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
