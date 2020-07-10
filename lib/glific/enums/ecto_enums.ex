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
