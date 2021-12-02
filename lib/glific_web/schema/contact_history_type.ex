defmodule GlificWeb.Schema.ContactHistoryTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact Group DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 2]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :contact_history_result do
    field(:contact_history, :contact_history)
    field(:errors, list_of(:input_error))
  end

  object :contact_history do
    field(:id, :id)
    field(:contact, :contact, do: resolve(dataloader(Repo, use_parent: true)))
    field(:event_type, :string)
    field(:event_label, :string)
    field(:event_meta, :json)
    field(:event_datetime, :datetime)
    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  object :contact_history_queries do
    @desc "Get a list of all contact histories"
    field :contact_histories, list_of(:contact_history) do
      arg(:contact_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Contacts.contact/3)
    end
  end
end
