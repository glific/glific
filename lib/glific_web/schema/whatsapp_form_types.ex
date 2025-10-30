defmodule GlificWeb.Schema.WhatsappFormTypes do
  @moduledoc """
  GraphQL Representation of Whatsapp From
  """
  use Absinthe.Schema.Notation
  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :whatsapp_form_mutations do
    @desc "Publish a WhatsApp form to Meta"
    field :publish_whatsapp_form, :publish_response do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&GlificWeb.Resolvers.WhatsappFormResolver.publish_whatsapp_form/3)
    end
  end

  object :publish_response do
    field :status, :string
    field :form, :whatsapp_form
  end
end
