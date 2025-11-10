defmodule GlificWeb.Schema.WhatsappFormTypes do
  @moduledoc """
  GraphQL Representation of Glific's WhatsApp Form DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :whatsapp_form do
    field :id, :id
    field :name, :string
    field :status, :whatsapp_form_status_enum
    field :description, :string
    field :definition, :json
    field :meta_flow_id, :string
    field :categories, list_of(:string)
    field(:errors, list_of(:input_error))
  end

  object :wa_form_response do
    field :status, :string
    field :body, :whatsapp_form
    field(:errors, list_of(:input_error))
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
    @desc "Get a count of all whatsapp forms filtered by various criteria"
    field :count_whatsapp_forms, :integer do
      arg(:filter, :whatsapp_form_filter)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.count_whatsapp_forms/3)
    end

    @desc "get the details of one whatsapp form by id"
    field :get_whatsapp_form_by_id, :whatsapp_form do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WhatsappForms.get_whatsapp_form_by_id/3)
    end

    @desc "Get a list of all whatsapp forms filtered by various criteria"
    field :list_whatsapp_forms, list_of(:whatsapp_form) do
      arg(:filter, :whatsapp_form_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WhatsappForms.list_whatsapp_forms/3)
    end
  end

  object :whatsapp_form_mutations do
    @desc "Publish a WhatsApp form to Meta"
    field :publish_whatsapp_form, :wa_form_response do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.publish_whatsapp_form/3)
    end

    @desc "Deactivate a WhatsApp Form"
    field :deactivate_wa_form, type: :wa_form_response do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.deactivate_wa_form/3)
    end
  end
end
