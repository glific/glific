defmodule GlificWeb.Schema.InteractiveTypes do
  @moduledoc """
  GraphQL Representation of Glific's Interactive DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias Glific.Messages.Interactive
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :interactive_result do
    field :interactive, :interactive
    field :errors, list_of(:input_error)
  end

  object :interactive do
    field :id, :id
    field :label, :string
    field :type, :string
    field :interactive_content, :json

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  @desc "Filtering options for interactives"
  input_object :interactive_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the type of interactive"
    field :type, :string
  end

  input_object :interactive_input do
    field :label, :string
    field :type, :string
    field :interactive_content, :json
  end

  object :interactive_queries do
    # field :whatsapp_hsm_categories, list_of(:string) do
    #   middleware(Authorize, :manager)

    #   resolve(fn _, _, _ ->
    #     {:ok, SessionTemplate.list_whatsapp_hsm_categories()}
    #   end)
    # end

    # @desc "get the details of one interactive"
    # field :interactive, :interactive_result do
    #   arg(:id, non_null(:id))
    #   middleware(Authorize, :staff)
    #   resolve(&Resolvers.Templates.interactive/3)
    # end

    @desc "Get a list of all interactives filtered by various criteria"
    field :interactives, list_of(:interactive) do
      arg(:filter, :interactive_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Interactives.interactives/3)
    end

    @desc "Get a count of all interactives filtered by various criteria"
    field :count_interactives, :integer do
      arg(:filter, :interactive_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Interactives.count_interactives/3)
    end
  end

  object :interactive_mutations do
    # field :create_interactive, :interactive_result do
    #   arg(:input, non_null(:interactive_input))
    #   middleware(Authorize, :staff)
    #   resolve(&Resolvers.Templates.create_interactive/3)
    # end

    # field :update_interactive, :interactive_result do
    #   arg(:id, non_null(:id))
    #   arg(:input, :interactive_input)
    #   middleware(Authorize, :staff)
    #   resolve(&Resolvers.Templates.update_interactive/3)
    # end

    # field :delete_interactive, :interactive_result do
    #   arg(:id, non_null(:id))
    #   middleware(Authorize, :staff)
    #   resolve(&Resolvers.Templates.delete_interactive/3)
    # end

    # field :create_template_form_message, :interactive_result do
    #   arg(:message_id, non_null(:id))
    #   arg(:input, :message_to_template_input)
    #   middleware(Authorize, :staff)
    #   resolve(&Resolvers.Templates.create_template_from_message/3)
    # end
  end
end
