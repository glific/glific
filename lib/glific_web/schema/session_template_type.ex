defmodule GlificWeb.Schema.SessionTemplateTypes do
  @moduledoc """
  GraphQL Representation of Glific's Session Template DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

  object :session_template_result do
    field :session_template, :session_template
    field :errors, list_of(:input_error)
  end

  object :session_template do
    field :id, :id
    field :label, :string
    field :body, :string
    field :shortcode, :string
    field :is_reserved, :boolean
    field :is_active, :boolean
    field :is_source, :boolean

    field :language, :language do
      resolve(dataloader(Repo))
    end

    field :message_media, :message_media do
      resolve(dataloader(Repo))
    end

    field :parent, :tag do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for session_templates"
  input_object :session_template_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the body of template"
    field :body, :string
  end

  input_object :session_template_input do
    field :label, :string
    field :body, :string
    field :shortcode, :string
    field :is_reserved, :boolean
    field :is_active, :boolean
    field :is_source, :boolean
    field :language_id, :id
  end

  object :session_template_queries do
    @desc "get the details of one session_template"
    field :session_template, :session_template_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Templates.session_template/3)
    end

    @desc "Get a list of all session_templates filtered by various criteria"
    field :session_templates, list_of(:session_template) do
      arg(:filter, :session_template_filter)
      arg(:order, type: :sort_order, default_value: :asc)
      resolve(&Resolvers.Templates.session_templates/3)
    end
  end

  object :session_template_mutations do
    field :create_session_template, :session_template_result do
      arg(:input, non_null(:session_template_input))
      resolve(&Resolvers.Templates.create_session_template/3)
    end

    field :update_session_template, :session_template_result do
      arg(:id, non_null(:id))
      arg(:input, :session_template_input)
      resolve(&Resolvers.Templates.update_session_template/3)
    end

    field :delete_session_template, :session_template_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Templates.delete_session_template/3)
    end
  end
end
