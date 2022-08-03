alias Glific.Repo
alias Glific.{Settings.Language, Tags.Tag, Search.Full}

alias Glific.{
  Messages,
  Flows,
  Flows.Flow,
  Flows.FlowContext,
  Contacts,
  Contacts.Contact,
  Profiles.Profile
}

import Ecto.Query

Glific.Repo.put_process_state(1)

onboard_params = %{
  "api_key" => "c6d46a2fef194d57cdd3403a9abc7bab",
  "app_name" => "tidescoloredcowproduction",
  "shortcode" => "abc",
  "email" => "abc@email.com",
  "phone" => "919917443994",
  "name" => "ABC"
}
