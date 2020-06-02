defmodule Glific.Enums do
  @moduledoc """
  The Enum provides a location for all enum related macros. All the constants that
  Ecto/Elixir used are exposed here as macros, so other files can invoke them as simple
  functions
  """

  # get all the enum constants into this module scope
  use Glific.Constants.Enums

  @doc ~S"""
  Lets ensure that the constants evaluate to some expected values

  ## Examples

  iex> Glific.Enums.api_status_const()
  [:ok, :error]

  iex> Glific.Enums.contact_status_const()
  [:failed, :invalid, :processing, :valid]

  iex> Glific.Enums.message_flow_const()
  [:inbound, :outbound]

  iex> Glific.Enums.message_status_const()
  [:sent, :delivered, :enqueued, :error, :read, :received]

  iex> Glific.Enums.message_types_const()
  [:audio, :contact, :document, :hsm, :image, :location, :text, :video]

  iex> Glific.Enums.sort_order_const()
  [:asc, :desc]

  We also test the ecto enums in this file, since they exist outside a module

  iex> Glific.APIStatusEnum.__enum_map__()
  Glific.Enums.api_status_const()

  iex> Glific.ContactStatusEnum.__enum_map__()
  Glific.Enums.contact_status_const()

  iex> Glific.MessageFlowEnum.__enum_map__()
  Glific.Enums.message_flow_const()

  iex> Glific.MessageStatusEnum.__enum_map__()
  Glific.Enums.message_status_const()

  iex> Glific.MessageTypesEnum.__enum_map__()
  Glific.Enums.message_types_const()

  iex> Glific.SortOrderEnum.__enum_map__()
  Glific.Enums.sort_order_const()

  """

  defmacro api_status_const,
    do: Macro.expand(@api_status_const, __CALLER__)

  defmacro contact_status_const,
    do: Macro.expand(@contact_status_const, __CALLER__)

  defmacro message_flow_const,
    do: Macro.expand(@message_flow_const, __CALLER__)

  defmacro message_status_const,
    do: Macro.expand(@message_status_const, __CALLER__)

  defmacro message_types_const,
    do: Macro.expand(@message_types_const, __CALLER__)

  defmacro sort_order_const,
    do: Macro.expand(@sort_order_const, __CALLER__)
end
