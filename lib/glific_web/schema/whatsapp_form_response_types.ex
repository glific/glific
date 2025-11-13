defmodule GlificWeb.Schema.WhatsappFormResponseTypes do
  @moduledoc """
  GraphQL Representation of Glific's WhatsApp Form Response DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 2]

  alias Glific.Repo

  object :whatsapp_form_response do
    field :id, :id
    field :contact_id, :id
    field :raw_response, :json
    field :whatsapp_form_id, :id
    field :submitted_at, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :message, :message do
      resolve(dataloader(Repo, use_parent: true))
    end
  end
end
