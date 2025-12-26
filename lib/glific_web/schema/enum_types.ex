defmodule GlificWeb.Schema.EnumTypes do
  @moduledoc """
  Representing our enums in the style Absinthe expects them. We can now use these
  atoms in the object definitions within the GraphQL Schema
  """

  use Absinthe.Schema.Notation

  require Glific.Enums

  # define all enums specifically for absinthere
  @desc "API Function Status enum"
  enum(:api_status_enum, values: Glific.Enums.api_status_const())

  @desc "The Contact Field Scope Types enum"
  enum(:contact_field_scope_enum, values: Glific.Enums.contact_field_scope_const())

  @desc "The Contact Field Value Types enum"
  enum(:contact_field_value_type_enum, values: Glific.Enums.contact_field_value_type_const())

  @desc "The Contact Status enum"
  enum(:contact_status_enum, values: Glific.Enums.contact_status_const())

  @desc "The Contact Provider Status enum"
  enum(:contact_provider_status_enum, values: Glific.Enums.contact_provider_status_const())

  @desc "The Flow Case enum"
  enum(:flow_case_enum, values: Glific.Enums.flow_case_const())

  @desc "The Flow Router enum"
  enum(:flow_router_enum, values: Glific.Enums.flow_router_const())

  @desc "The Flow action Type enum"
  enum(:flow_action_type_enum, values: Glific.Enums.flow_action_type_const())

  @desc "The Flow Type enum"
  enum(:flow_type_enum, values: Glific.Enums.flow_type_const())

  @desc "The Message Flow enum"
  enum(:message_flow_enum, values: Glific.Enums.message_flow_const())

  @desc "The Message Status enum"
  enum(:message_status_enum, values: Glific.Enums.message_status_const())

  @desc "The Message Types enum"
  enum(:message_type_enum, values: Glific.Enums.message_type_const())

  @desc "The Template Button Type enum"
  enum(:template_button_type_enum, values: Glific.Enums.template_button_type_const())

  @desc "Enum for question types"
  enum(:question_type_enum, values: Glific.Enums.question_type_const())

  @desc "The Organization Status enum"
  enum(:organization_status_enum, values: Glific.Enums.organization_status_const())

  @desc "The Interactive Message Types enum"
  enum(:interactive_message_type_enum, values: Glific.Enums.interactive_message_type_const())

  @desc "The Import Contact Types enum"
  enum(:import_contacts_type_enum, values: Glific.Enums.import_contacts_type_const())

  # doing this in a special way, since values: does not work
  # if we are using default values
  @desc "Enum for ordering results"
  enum :sort_order do
    value(:asc)
    value(:desc)
  end

  @desc "The Certificate template Types enum"
  enum(:certificate_template_type_enum, values: Glific.Enums.certificate_template_type_const())

  @desc "The sheet sync status enum"
  enum(:sheet_sync_status_enum, values: Glific.Enums.sheet_sync_status_const())

  @desc "The WhatsApp Form Status enum"
  enum(:whatsapp_form_status_enum, values: Glific.Enums.whatsapp_form_status_const())

  @desc "The WhatsApp Form Category enum"
  enum(:whatsapp_form_category_enum, values: Glific.Enums.whatsapp_form_category_const())
end
