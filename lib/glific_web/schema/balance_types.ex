defmodule GlificWeb.Schema.BalanceTypes do
  @moduledoc """
  GraphQL Representation of Glific's Message DataType
  """
  alias Glific.Communications

  object :gupshup_balance do
    field :balance, :string do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(&Communications.publish_data/3)
    end

end
