defmodule GlificWeb.Schema.WhatsappFormsRevisionTypes do
  @moduledoc """
  GraphQL Representation of Glific's WhatsApp Form Revision DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  input_object :whatsapp_form_revision_input do
    field(:whatsapp_form_id, non_null(:id))
    field(:definition, non_null(:json))
  end

  object :whatsapp_form_revision do
    field(:id, :id)
    field(:whatsapp_form_id, :id)
    field(:definition, :json)
    field(:revision_number, :integer)
    field(:user_id, :id)
    field(:inserted_at, :string)
    field(:updated_at, :string)
  end

  object :whatsapp_form_revision_result do
    field(:whatsapp_form_revision, :whatsapp_form_revision)
    field(:errors, list_of(:input_error))
  end

  object :whatsapp_form_revision_queries do
    @desc "Get a specific WhatsApp form revision by ID"
    field :whatsapp_form_revision, :whatsapp_form_revision_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappFormsRevisions.whatsapp_form_revision/3)
    end

    @desc "List revisions for a WhatsApp form (last 10 by default)"
    field :list_whatsapp_form_revisions, list_of(:whatsapp_form_revision) do
      arg(:whatsapp_form_id, non_null(:id))
      arg(:limit, :integer, default_value: 10)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappFormsRevisions.list_revisions/3)
    end
  end

  object :whatsapp_form_revision_mutations do
    @desc "Save a WhatsApp form revision"
    field :save_whatsapp_form_revision, :whatsapp_form_revision_result do
      arg(:input, non_null(:whatsapp_form_revision_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappFormsRevisions.save_revision/3)
    end

    @desc "Revert a WhatsApp form to a specific revision"
    field :revert_to_whatsapp_form_revision, :whatsapp_form_revision_result do
      arg(:whatsapp_form_id, non_null(:id))
      arg(:revision_id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.WhatsappFormsRevisions.revert_to_revision/3)
    end
  end
end
