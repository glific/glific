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
  [:blocked, :failed, :invalid, :processing, :valid]

  iex> Glific.Enums.contact_provider_status_const()
  [:none, :session, :session_and_hsm, :hsm]

  iex> Glific.Enums.flow_case_const()
  [:has_any_word]

  iex> Glific.Enums.flow_router_const()
  [:switch]

  iex> Glific.Enums.flow_action_type_const()
  [:enter_flow, :send_msg, :set_contact_language, :wait_for_response,
  :set_contact_field]

  iex> Glific.Enums.flow_type_const()
  [:message]

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

  iex> Glific.Enums.ContactProviderStatus.__enum_map__()
  Glific.Enums.contact_provider_status_const()

  iex> Glific.Enums.FlowCase.__enum_map__()
  Glific.Enums.flow_case_const()

  iex> Glific.Enums.FlowRouter.__enum_map__()
  Glific.Enums.flow_router_const()

  iex> Glific.Enums.FlowActionType.__enum_map__()
  Glific.Enums.flow_action_type_const()

  iex> Glific.Enums.FlowType.__enum_map__()
  Glific.Enums.flow_type_const()

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

  iex> Glific.Enums.ContactFieldValueType.__enum_map__()
  Glific.Enums.contact_field_value_type_const()

  iex> Glific.Enums.ContactFieldScope.__enum_map__()
  Glific.Enums.contact_field_scope_const()

  """

  defmacro api_status_const,
    do: Macro.expand(@api_status_const, __CALLER__)

  defmacro contact_status_const,
    do: Macro.expand(@contact_status_const, __CALLER__)

  defmacro contact_provider_status_const,
    do: Macro.expand(@contact_provider_status_const, __CALLER__)

  defmacro flow_case_const,
    do: Macro.expand(@flow_case_const, __CALLER__)

  defmacro flow_router_const,
    do: Macro.expand(@flow_router_const, __CALLER__)

  defmacro flow_action_type_const,
    do: Macro.expand(@flow_action_type_const, __CALLER__)

  defmacro flow_type_const,
    do: Macro.expand(@flow_type_const, __CALLER__)

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

  defmacro contact_field_value_type_const,
    do: Macro.expand(@contact_field_value_type_const, __CALLER__)

  defmacro contact_field_scope_const,
    do: Macro.expand(@contact_field_scope_const, __CALLER__)
end
