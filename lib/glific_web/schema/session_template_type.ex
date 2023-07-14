defmodule GlificWeb.Schema.SessionTemplateTypes do
  @moduledoc """
  GraphQL Representation of Glific's Session Template DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias Glific.Templates
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :session_template_result do
    field :session_template, :session_template
    field :errors, list_of(:input_error)
  end

  object :import_templates_result do
    field :status, :string
    field :errors, list_of(:input_error)
  end

  object :bulk_apply_templates_result do
    field :csv_rows, :string
    field :errors, list_of(:input_error)
  end

  object :sync_hsm_templates do
    field :message, :string
    field :errors, list_of(:input_error)
  end

  object :session_template do
    field :id, :id
    field :bsp_id, :string
    field :label, :string
    field :body, :string
    field :type, :message_type_enum
    field :shortcode, :string
    field :is_hsm, :boolean
    field :status, :string
    field :number_parameters, :integer
    field :category, :string
    field :example, :string
    field :is_reserved, :boolean
    field :is_active, :boolean
    field :is_source, :boolean
    field :translations, :json
    field :has_buttons, :boolean
    field :button_type, :template_button_type_enum
    field :buttons, :json
    field :reason, :string

    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :tag, :tag do
      resolve(dataloader(Repo))
    end

    field :language, :language do
      resolve(dataloader(Repo))
    end

    field :message_media, :message_media do
      resolve(dataloader(Repo))
    end

    field :parent, :session_template do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for session_templates"
  input_object :session_template_filter do
    @desc "Match term with label and associated tag of template"
    field(:term, :string)

    @desc "Match the label"
    field(:label, :string)

    @desc "Match the tag_ids"
    field(:tag_ids, list_of(:integer))

    @desc "Match the body of template"
    field(:body, :string)

    @desc "Match the shortcode of template"
    field(:shortcode, :string)

    @desc "Match the hsm template message"
    field(:is_hsm, :boolean)

    @desc "Match the category of the template"
    field(:category, :string)

    @desc "Match the parent"
    field(:parent, :string)

    @desc "Match the parent"
    field(:parent_id, :integer)

    @desc "Match a language"
    field(:language, :string)

    @desc "Match a language id"
    field(:language_id, :integer)

    @desc "Match status of hsm"
    field(:status, :string)

    @desc "Match the active flag"
    field(:is_active, :boolean)

    @desc "Match the reserved flag"
    field(:is_reserved, :boolean)

    @desc "a static date range input field which will apply on updated at column."
    field(:date_range, :date_range_input)
  end

  input_object :session_template_input do
    field :label, :string
    field :body, :string
    field :type, :message_type_enum
    field :shortcode, :string
    field :is_hsm, :boolean
    field :category, :string
    field :example, :string
    field :is_active, :boolean
    field :is_source, :boolean
    field :message_media_id, :id
    field :language_id, :id
    field :tag_id, :id
    field :translations, :json
    field :has_buttons, :boolean
    field :button_type, :template_button_type_enum
    field :buttons, :json
  end

  input_object :edit_approved_template_input do
    field :content, :string
    field :example, :string
    field :template_ype, :string
    field :enable_sample, :string
    field :header, :string
    field :footer, :string
    field :category, :string
  end

  input_object :message_to_template_input do
    field :label, :string
    field :shortcode, :string
    field :language_id, :id
  end

  object :session_template_queries do
    field :whatsapp_hsm_categories, list_of(:string) do
      middleware(Authorize, :manager)

      resolve(fn _, _, _ ->
        {:ok, Templates.list_whatsapp_hsm_categories()}
      end)
    end

    @desc "get the details of one session_template"
    field :session_template, :session_template_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.session_template/3)
    end

    @desc "Get a list of all session_templates filtered by various criteria"
    field :session_templates, list_of(:session_template) do
      arg(:filter, :session_template_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.session_templates/3)
    end

    @desc "Get a count of all session_templates filtered by various criteria"
    field :count_session_templates, :integer do
      arg(:filter, :session_template_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.count_session_templates/3)
    end
  end

  object :session_template_mutations do
    field :create_session_template, :session_template_result do
      arg(:input, non_null(:session_template_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.create_session_template/3)
    end

    @desc "sync hsm with bsp"
    field :sync_hsm_template, :sync_hsm_templates do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.sync_hsm_template/3)
    end

    field :update_session_template, :session_template_result do
      arg(:id, non_null(:id))
      arg(:input, :session_template_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.update_session_template/3)
    end

    field :edit_approved_template, :session_template_result do
      arg(:id, non_null(:id))
      arg(:input, :edit_approved_template_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.edit_approved_template/3)
    end

    field :delete_session_template, :session_template_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.delete_session_template/3)
    end

    field :create_template_form_message, :session_template_result do
      arg(:message_id, non_null(:id))
      arg(:input, :message_to_template_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.create_template_from_message/3)
    end

    field :import_templates, :import_templates_result do
      arg(:data, :string)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.import_templates/3)
    end

    field :bulk_apply_templates, :bulk_apply_templates_result do
      arg(:data, :string)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Templates.bulk_apply_templates/3)
    end
  end
end
