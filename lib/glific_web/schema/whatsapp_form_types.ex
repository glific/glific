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
    field :meta_flow_id, :string
    field :categories, list_of(:string)
  end

  object :wa_response do
    field :status, :string
    field :body, :whatsapp_form
    field(:errors, list_of(:input_error))
  end

  object :whatsapp_form_mutations do
    @desc "Publish a WhatsApp form to Meta"
    field :publish_whatsapp_form, :wa_response do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappForms.publish_whatsapp_form/3)
    end

    @desc "Deactivate a WhatsApp Form"
    field :deactivate_wa_form, type: :wa_response do
      arg(:form_id, non_null(:id))
      resolve(&Resolvers.WhatsappForms.deactivate_wa_form/3)
    end
  end
end
