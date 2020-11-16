defmodule GlificWeb.Schema.BalanceTypes do
  @moduledoc """
  GraphQL Representation of Glific's Message DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Communications

  alias GlificWeb.{
    Schema,
  }
  object :bsp_balance do
    field :balance, :string do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(&Communications.publish_data/3)
    end
  end

end
