defmodule GlificWeb.Schema.InteractiveTypes do
  @moduledoc """
  GraphQL Representation of Glific's Interactive DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :interactive_result do
    field :interactive, :interactive
    field :errors, list_of(:input_error)
  end

  object :interactive do
    field :id, :id
    field :label, :string
    field :type, :interactive_message_type_enum
    field :interactive_content, :json

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  @desc "Filtering options for interactives"
  input_object :interactive_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the type of interactive"
    field :type, :interactive_message_type_enum
  end

  input_object :interactive_input do
    field :label, :string
    field :type, :interactive_message_type_enum
    field :interactive_content, :json
  end

  object :interactive_template_queries do
    @desc "get the details of one interactive"
    field :interactive, :interactive_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.interactive/3)
    end

    @desc "Get a list of all interactives filtered by various criteria"
    field :interactives, list_of(:interactive) do
      arg(:filter, :interactive_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.interactives/3)
    end

    @desc "Get a count of all interactives filtered by various criteria"
    field :count_interactives, :integer do
      arg(:filter, :interactive_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.count_interactives/3)
    end
  end

  object :interactive_template_mutations do
    field :create_interactive_template, :interactive_result do
      arg(:input, non_null(:interactive_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.create_interactive_template/3)
    end

    field :update_interactive_template, :interactive_result do
      arg(:id, non_null(:id))
      arg(:input, :interactive_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.update_interactive_template/3)
    end

    field :delete_interactive_template, :interactive_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.delete_interactive_template/3)
    end
  end
end
