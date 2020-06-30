defmodule Glific.Enums do
  @moduledoc """
  The Enum provides a location for all enum related macros. All the constants that
  Ecto/Elixir used are exposed here as macros, so other files can invoke them as simple
  functions
  """

  # get all the enum constants into this module scope
  use Glific.Enums.Constants

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
  [:sent, :delivered, :enqueued, :error, :read, :received, :contact_opt_out]

  iex> Glific.Enums.message_type_const()
  [:audio, :contact, :document, :hsm, :image, :location, :text, :video]

  iex> Glific.Enums.question_type_const()
  [:text, :numeric, :date]

  iex> Glific.Enums.sort_order_const()
  [:asc, :desc]

  We also test the ecto enums in this file, since they exist outside a module

  iex> Glific.Enums.APIStatus.__enum_map__()
  Glific.Enums.api_status_const()

  iex> Glific.Enums.ContactStatus.__enum_map__()
  Glific.Enums.contact_status_const()

  iex> Glific.Enums.MessageFlow.__enum_map__()
  Glific.Enums.message_flow_const()

  iex> Glific.Enums.MessageStatus.__enum_map__()
  Glific.Enums.message_status_const()

  iex> Glific.Enums.MessageType.__enum_map__()
  Glific.Enums.message_type_const()

  iex> Glific.Enums.QuestionType.__enum_map__()
  Glific.Enums.question_type_const()

  iex> Glific.Enums.SortOrder.__enum_map__()
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

  defmacro message_type_const,
    do: Macro.expand(@message_type_const, __CALLER__)

  defmacro question_type_const,
    do: Macro.expand(@question_type_const, __CALLER__)

  defmacro sort_order_const,
    do: Macro.expand(@sort_order_const, __CALLER__)
end
