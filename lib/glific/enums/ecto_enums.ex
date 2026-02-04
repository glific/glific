# Build the enums for ecto to consume in an easy manner
# this is in a slightly different format than elixir and uses
# the structure exposed to by EctoEnum

import EctoEnum

require Glific.Enums

defenum(
  Glific.Enums.APIStatus,
  :api_status_enum,
  Glific.Enums.api_status_const()
)

defenum(
  Glific.Enums.ContactStatus,
  :contact_status_enum,
  Glific.Enums.contact_status_const()
)

# we can rename provider status enum to bsp status enum
# but it seems a bit tricky to rename enums without touching the old migrations
# so for now we use provider status enum for bsp status fields
defenum(
  Glific.Enums.ContactProviderStatus,
  :contact_provider_status_enum,
  Glific.Enums.contact_provider_status_const()
)

defenum(
  Glific.Enums.FlowCase,
  :flow_case_enum,
  Glific.Enums.flow_case_const()
)

defenum(
  Glific.Enums.FlowRouter,
  :flow_router_enum,
  Glific.Enums.flow_router_const()
)

defenum(
  Glific.Enums.FlowActionType,
  :flow_action_type_enum,
  Glific.Enums.flow_action_type_const()
)

defenum(
  Glific.Enums.FlowType,
  :flow_type_enum,
  Glific.Enums.flow_type_const()
)

defenum(
  Glific.Enums.MessageFlow,
  :message_flow_enum,
  Glific.Enums.message_flow_const()
)

defenum(
  Glific.Enums.MessageStatus,
  :message_status_enum,
  Glific.Enums.message_status_const()
)

defenum(
  Glific.Enums.MessageType,
  :message_type_enum,
  Glific.Enums.message_type_const()
)

defenum(
  Glific.Enums.QuestionType,
  :question_type_enum,
  Glific.Enums.question_type_const()
)

defenum(
  Glific.Enums.SortOrder,
  :sort_order_enum,
  Glific.Enums.sort_order_const()
)

defenum(
  Glific.Enums.ContactFieldValueType,
  :contact_field_value_type_enum,
  Glific.Enums.contact_field_value_type_const()
)

defenum(
  Glific.Enums.ContactFieldScope,
  :contact_field_scope_enum,
  Glific.Enums.contact_field_scope_const()
)

defenum(
  Glific.Enums.UserRoles,
  :user_roles_enum,
  Glific.Enums.user_roles_const()
)

defenum(
  Glific.Enums.TemplateButtonType,
  :template_button_type_enum,
  Glific.Enums.template_button_type_const()
)

defenum(
  Glific.Enums.OrganizationStatus,
  :organization_status_enum,
  Glific.Enums.organization_status_const()
)

defenum(
  Glific.Enums.InteractiveMessageType,
  :interactive_message_type_enum,
  Glific.Enums.interactive_message_type_const()
)

defenum(
  Glific.Enums.ImportContactsType,
  :import_contacts_type_enum,
  Glific.Enums.import_contacts_type_const()
)

defenum(
  Glific.Enums.CertificateTemplateType,
  :certificate_template_type_enum,
  Glific.Enums.certificate_template_type_const()
)

defenum(
  Glific.Enums.SheetSyncStatus,
  :sheet_sync_status_enum,
  Glific.Enums.sheet_sync_status_const()
)

defenum(
  Glific.Enums.WhatsappFormStatus,
  :whatsapp_form_status_enum,
  Glific.Enums.whatsapp_form_status_const()
)

defenum(
  Glific.Enums.WhatsappFormCategory,
  :whatsapp_form_category_enum,
  Glific.Enums.whatsapp_form_category_const()
)

defenum(
  Glific.Enums.AssistantConfigVersionStatus,
  :assistant_config_version_status_enum,
  Glific.Enums.assistant_config_version_status_const()
)

defenum(
  Glific.Enums.KnowledgeBaseStatus,
  :knowledge_base_status_enum,
  Glific.Enums.knowledge_base_status_const()
)
