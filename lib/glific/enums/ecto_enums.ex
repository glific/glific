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
