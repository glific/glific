defmodule GlificWeb.Schema.InteractiveTemplateTypes do
  @moduledoc """
  GraphQL Representation of Glific's Interactive DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :interactive_template_result do
    field :interactive_template, :interactive_template
    field :errors, list_of(:input_error)
  end

  object :interactive_template do
    field :id, :id
    field :label, :string
    field :type, :interactive_message_type_enum
    field :interactive_content, :json

    field :inserted_at, :datetime
    field :updated_at, :datetime
    field :translations, :json

    field :language, :language do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for interactives"
  input_object :interactive_template_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the type of interactive"
    field :type, :interactive_message_type_enum

    @desc "Match a language"
    field :language, :string

    @desc "Match a language id"
    field :language_id, :integer
  end

  input_object :interactive_template_input do
    field :label, :string
    field :type, :interactive_message_type_enum
    field :interactive_content, :json
    field :language_id, :id
    field :translations, :json
  end

  object :interactive_template_queries do
    @desc "get the details of one interactive template"
    field :interactive_template, :interactive_template_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.interactive_template/3)
    end

    @desc "Get a list of all interactive templates filtered by various criteria"
    field :interactive_templates, list_of(:interactive_template) do
      arg(:filter, :interactive_template_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.interactive_templates/3)
    end

    @desc "Get a count of all interactives filtered by various criteria"
    field :count_interactive_templates, :integer do
      arg(:filter, :interactive_template_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.count_interactive_templates/3)
    end
  end

  object :interactive_template_mutations do
    field :create_interactive_template, :interactive_template_result do
      arg(:input, non_null(:interactive_template_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.create_interactive_template/3)
    end

    field :update_interactive_template, :interactive_template_result do
      arg(:id, non_null(:id))
      arg(:input, :interactive_template_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.update_interactive_template/3)
    end

    field :delete_interactive_template, :interactive_template_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.InterativeTemplates.delete_interactive_template/3)
    end
  end
end
