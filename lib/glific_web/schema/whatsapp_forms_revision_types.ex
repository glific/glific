defmodule GlificWeb.Schema.WhatsappFormsRevisionTypes do
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  input_object :whatsapp_form_revision_input do
    field :whatsapp_form_id, non_null(:id)
    field :definition, non_null(:json)
  end

  object :whatsapp_form_revision do
    field :whatsapp_form, :whatsapp_form
  end

  object :whatsapp_form_revision_mutations do
    @desc "Save a WhatsApp form revision"
    field :save_whatsapp_form_revision, :whatsapp_form_revision do
      arg(:input, non_null(:whatsapp_form_revision_input))
      resolve(&Resolvers.WhatsappFormsRevisions.save_revision/3)
    end
  end
end
