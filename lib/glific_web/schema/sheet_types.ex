defmodule GlificWeb.Schema.SheetTypes do
  @moduledoc """
  GraphQL Representation of Glific's Sheet DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :sheet_result do
    field :sheet, :sheet
    field :errors, list_of(:input_error)
  end

  object :sheet do
    field :id, :id
    field :label, :string
    field :url, :string
    field :data, :map
    field :synced_at, :datetime
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  input_object :sheet_input do
    field :label, :string
    field :url, :string
  end

  object :sheet_queries do
    field :trigger, :trigger_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Sheets.sheet/3)
    end
  end

  object :sheet_mutations do
    field :create_sheet, :sheet_result do
      arg(:input, non_null(:sheet_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Sheets.create_sheet/3)
    end
  end
end
