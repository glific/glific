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
  [:sent, :delivered, :enqueued, :error, :read, :received, :contact_opt_out, :reached, :seen, :played, :deleted]

  iex> Glific.Enums.message_type_const()
  [:audio, :contact, :document, :hsm, :image, :location, :list, :quick_reply, :text, :video, :sticker, :location_request_message, :poll, :whatsapp_form_response]

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

  iex> Glific.Enums.UserRoles.__enum_map__()
  Glific.Enums.user_roles_const()

  iex> Glific.Enums.TemplateButtonType.__enum_map__()
  Glific.Enums.template_button_type_const()

  iex> Glific.Enums.OrganizationStatus.__enum_map__()
  Glific.Enums.organization_status_const()

  iex> Glific.Enums.InteractiveMessageType.__enum_map__()
  Glific.Enums.interactive_message_type_const()

  iex> Glific.Enums.ImportContactsType.__enum_map__()
  Glific.Enums.import_contacts_type_const()

  iex> Glific.Enums.certificate_template_type_const()
  [:slides]

  iex> Glific.Enums.SheetSyncStatus.__enum_map__()
  Glific.Enums.sheet_sync_status_const()

  iex> Glific.Enums.WhatsappFormStatus.__enum_map__()
  Glific.Enums.whatsapp_form_status_const()

  iex> Glific.Enums.WhatsappFormCategory.__enum_map__()
  Glific.Enums.whatsapp_form_category_const()
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

  defmacro user_roles_const,
    do: Macro.expand(@user_roles_const, __CALLER__)

  defmacro template_button_type_const,
    do: Macro.expand(@template_button_type_const, __CALLER__)

  defmacro organization_status_const,
    do: Macro.expand(@organization_status_const, __CALLER__)

  defmacro interactive_message_type_const,
    do: Macro.expand(@interactive_message_type_const, __CALLER__)

  defmacro import_contacts_type_const,
    do: Macro.expand(@import_contacts_type_const, __CALLER__)

  defmacro certificate_template_type_const,
    do: Macro.expand(@certificate_template_type_const, __CALLER__)

  defmacro sheet_sync_status_const,
    do: Macro.expand(@sheet_sync_status_const, __CALLER__)

  defmacro whatsapp_form_status_const,
    do: Macro.expand(@whatsapp_form_status_const, __CALLER__)

  defmacro whatsapp_form_category_const,
    do: Macro.expand(@whatsapp_form_category_const, __CALLER__)
end
