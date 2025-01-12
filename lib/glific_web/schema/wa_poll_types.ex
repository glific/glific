defmodule GlificWeb.Schema.WaPollTypes do
  @moduledoc """
  GraphQL Representation of Glific's whatsapp poll DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :wa_poll do
    field :id, :id
    field :label, :string
    field :poll_content, :json
    field :allow_multiple_answer, :boolean
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :wa_poll_result do
    field :wa_poll, :wa_poll
    field :errors, list_of(:input_error)
  end

  @desc "Filtering options for wa polls"
  input_object :wa_poll_filter do
    @desc "Match the label"
    field(:label, :string)

    @desc "Match the allow multiple answer"
    field(:allow_multiple_answer, :boolean)
  end

  input_object :wa_poll_input do
    field :id, :id
    field :label, :string
    field :poll_content, :json
    field :allow_multiple_answer, :boolean

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :wa_poll_queries do
    @desc "get the details of one whatsapp poll"
    field :wa_poll, :wa_poll_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaPoll.wa_poll/3)
    end

    @desc "Get a list of all wa polls filtered by various criteria"
    field :wa_polls, list_of(:wa_poll) do
      arg(:filter, :wa_poll_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaPoll.wa_polls/3)
    end

    @desc "Get a count of all wa polls filtered by various criteria"
    field :count_wa_polls, :integer do
      arg(:filter, :wa_poll_filter)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WaPoll.count_wa_polls/3)
    end
  end

  object :wa_poll_mutations do
    field :create_wa_poll, :wa_poll_result do
      arg(:input, non_null(:wa_poll_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WaPoll.create_wa_poll/3)
    end

    field :delete_wa_poll, :wa_poll_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WaPoll.delete_wa_poll/3)
    end

    field :copy_wa_poll, :wa_poll_result do
      arg(:id, non_null(:id))
      arg(:input, :wa_poll_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WaPoll.copy_wa_poll/3)
    end
  end
end
