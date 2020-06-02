# Build the enums for ecto to consume in an easy manner
# this is in a slightly different format than elixir and uses
# the structure exposed to by EctoEnum

import EctoEnum

require Glific.Enums

defenum(
  Glific.APIStatusEnum,
  :api_status_enum,
  Glific.Enums.api_status_const()
)

defenum(
  Glific.ContactStatusEnum,
  :contact_status_enum,
  Glific.Enums.contact_status_const()
)

defenum(
  Glific.MessageFlowEnum,
  :message_flow_enum,
  Glific.Enums.message_flow_const()
)

defenum(
  Glific.MessageStatusEnum,
  :message_status_enum,
  Glific.Enums.message_status_const()
)

defenum(
  Glific.MessageTypesEnum,
  :message_types_enum,
  Glific.Enums.message_types_const()
)

defenum(
  Glific.SortOrderEnum,
  :sort_order_enum,
  Glific.Enums.sort_order_const()
)
