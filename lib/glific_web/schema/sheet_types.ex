defmodule GlificWeb.Schema.SheetTypes do
  @moduledoc """
  GraphQL Representation of Glific's Sheet DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :sheet_result do
    field(:sheet, :sheet)
    field(:errors, list_of(:input_error))
  end

  object :sheet do
    field(:id, :id)
    field(:label, :string)
    field(:url, :string)
    field(:type, :string)
    field(:is_active, :boolean)
    field(:last_synced_at, :datetime)
    field(:auto_sync, :boolean)
    field(:sync_status, :sheet_sync_status_enum)
    field(:failure_reason, :string)
    field(:sheet_data_count, :integer)
    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  @desc "Filtering options for sheets"
  input_object :sheet_filter do
    @desc "Match the label"
    field(:label, :string)

    @desc "Match isActive flag"
    field(:is_active, :boolean)

    @desc "Match type flag"
    field(:type, :string)
  end

  input_object :sheet_input do
    field(:label, :string)
    field(:url, :string)
    field(:is_active, :boolean)
    field(:auto_sync, :boolean)
    field(:type, :string)
  end

  object :sheet_queries do
    field :sheet, :sheet_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Sheets.sheet/3)
    end

    field :sheets, list_of(:sheet) do
      arg(:filter, :sheet_filter)
      arg(:opts, :opts)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Sheets.sheets/3)
    end

    field :count_sheets, :integer do
      arg(:filter, :sheet_filter)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Sheets.count_sheets/3)
    end
  end

  object :sheet_mutations do
    field :create_sheet, :sheet_result do
      arg(:input, non_null(:sheet_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Sheets.create_sheet/3)
    end

    field :update_sheet, :sheet_result do
      arg(:id, non_null(:id))
      arg(:input, non_null(:sheet_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Sheets.update_sheet/3)
    end

    field :sync_sheet, :sheet_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Sheets.sync_sheet/3)
    end

    field :delete_sheet, :sheet_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Sheets.delete_sheet/3)
    end
  end
end
