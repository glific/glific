defmodule GlificWeb.Schema.WhatsappFormTypes do
  @moduledoc """
  GraphQL Representation of Glific's WhatsApp Form DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 2]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :whatsapp_form do
    field(:id, :id)
    field(:name, :string)
    field(:status, :whatsapp_form_status_enum)
    field(:description, :string)
    field(:meta_flow_id, :string)
    field(:categories, list_of(:string))
    field(:sheet_id, :id)
    field(:revision_id, :integer)
    field(:inserted_at, :string)
    field(:updated_at, :string)

    field(:errors, list_of(:input_error))

    field :sheet, :sheet do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :revision, :whatsapp_form_revision do
      resolve(dataloader(Repo, use_parent: true))
    end
  end

  object :whatsapp_form_result do
    field(:whatsapp_form, :whatsapp_form)
    field(:errors, list_of(:input_error))
  end

  input_object :whatsapp_form_input do
    field(:name, non_null(:string))
    field(:categories, non_null(list_of(:string)))
    field(:description, :string)
    field(:google_sheet_url, :string)
  end

  @desc "Filtering options for WhatsApp forms"
  input_object :whatsapp_form_filter do
    @desc "Match the name"
    field(:name, :string)

    @desc "Match the meta flow id"
    field(:meta_flow_id, :string)

    @desc "Match the status"
    field(:status, :whatsapp_form_status_enum)
  end

  object :whatsapp_form_queries do
    @desc "Get a WhatsApp form by ID"
    field :whatsapp_form, :whatsapp_form_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.whatsapp_form/3)
    end

    @desc "List all available WhatsApp form categories"
    field :whatsapp_form_categories, list_of(:string) do
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.list_whatsapp_form_categories/3)
    end

    @desc "Get a count of all whatsapp forms filtered by various criteria"
    field :count_whatsapp_forms, :integer do
      arg(:filter, :whatsapp_form_filter)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.count_whatsapp_forms/3)
    end

    @desc "Get a list of all whatsapp forms filtered by various criteria"
    field :list_whatsapp_forms, list_of(:whatsapp_form) do
      arg(:filter, :whatsapp_form_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WhatsappForms.list_whatsapp_forms/3)
    end
  end

  object :whatsapp_form_mutations do
    @desc "Create a WhatsApp form"
    field :create_whatsapp_form, :whatsapp_form_result do
      arg(:input, non_null(:whatsapp_form_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.create_whatsapp_form/3)
    end

    @desc "Update a WhatsApp form"
    field :update_whatsapp_form, :whatsapp_form_result do
      arg(:id, non_null(:id))
      arg(:input, non_null(:whatsapp_form_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.update_whatsapp_form/3)
    end

    @desc "Publish a WhatsApp form to Meta"
    field :publish_whatsapp_form, :whatsapp_form_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.publish_whatsapp_form/3)
    end

    @desc "Deactivate a WhatsApp Form"
    field :deactivate_whatsapp_form, type: :whatsapp_form_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.deactivate_whatsapp_form/3)
    end

    @desc "Activate a WhatsApp Form"
    field :activate_whatsapp_form, type: :whatsapp_form_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.activate_whatsapp_form/3)
    end

    @desc "Delete a WhatsApp Form"
    field :delete_whatsapp_form, :whatsapp_form_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.delete_whatsapp_form/3)
    end
  end
end
