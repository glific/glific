defmodule GlificWeb.Schema.EnumTypes do
  @moduledoc """
  Lets represent our enums in the style Absinthe expects them. We can now use these
  atoms in the object definitions within the GraphQL Schema
  """

  use Absinthe.Schema.Notation

  require Glific.Enums

  # define all enums specifically for absinthere
  @desc "API Function Status enum"
  enum(:api_status_enum, values: Glific.Enums.api_status_const())

  @desc "The Contact Status enum"
  enum(:contact_status_enum, values: Glific.Enums.contact_status_const())

  @desc "The Message Flow enum"
  enum(:message_flow_enum, values: Glific.Enums.message_flow_const())

  @desc "The Message Status enum"
  enum(:message_status_enum, values: Glific.Enums.message_status_const())

  @desc "The Message Types enum"
  enum(:message_types_enum, values: Glific.Enums.message_types_const())

  @desc "Enum for ordering results"
  enum(:sort_order, values: Glific.Enums.sort_order_const())
end
