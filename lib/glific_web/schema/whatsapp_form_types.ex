defmodule GlificWeb.Schema.WhatsappFormTypes do
  @moduledoc """
  GraphQL Representation of Glific's WhatsApp Form DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  object :whatsapp_form_result do
    field :whatsapp_form, :whatsapp_form
    field :errors, list_of(:input_error)
  end

  object :whatsapp_form do
    field :id, :string
    field :name, :string
    field :status, :string
    field :categories, list_of(:string)
    field :definition, :json
    field :inserted_at, :string
    field :updated_at, :string
    field :description, :string
    field :meta_flow_id, :string
  end

  input_object :whatsapp_form_input do
    field :name, non_null(:string)
    field :flow_json, non_null(:json)
    field :categories, non_null(list_of(:string))
    field :description, :string
  end

  object :whatsapp_form_queries do

    @desc "Get a WhatsApp form by ID"
    field :whatsapp_form, :whatsapp_form_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.WhatsappForms.whatsapp_form/3)
    end

    @desc "List all available WhatsApp form categories"
    field :whatsapp_form_categories, list_of(:string) do
      resolve(&Resolvers.WhatsappForms.list_whatsapp_form_categories/3)
    end
  end

  object :whatsapp_form_mutations do
    @desc "Create a WhatsApp form"
    field :create_whatsapp_form, :whatsapp_form_result do
      arg(:input, non_null(:whatsapp_form_input))
      resolve(&Resolvers.WhatsappForms.create_whatsapp_form/3)
    end

    @desc "Update a WhatsApp form"
    field :update_whatsapp_form, :whatsapp_form_result do
      arg(:id, non_null(:id))
      arg(:input, non_null(:whatsapp_form_input))
      resolve(&Resolvers.WhatsappForms.update_whatsapp_form/3)
    end
  end
end
