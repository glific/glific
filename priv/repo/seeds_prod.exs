# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds_prod.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Glific.Repo.insert!(%Glific.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Glific.{
  Contacts.Contact,
  Flows.Flow,
  Flows.FlowRevision,
  Partners.Organization,
  Partners.Provider,
  Repo,
  Searches.SavedSearch,
  Settings.Language,
  Tags.Tag,
  Templates.SessionTemplate,
  Users
}

# seed languages
hi = Repo.insert!(%Language{label: "Hindi", label_locale: "हिंदी", locale: "hi"})

en_us =
  Repo.insert!(%Language{
    label: "English (United States)",
    label_locale: "English",
    locale: "en_US"
  })

# seed tags
message_tags_mt = Repo.insert!(%Tag{label: "Messages", language: en_us})
message_tags_ct = Repo.insert!(%Tag{label: "Contacts", language: en_us})

tags = [
  # Intent of message
  %{label: "Compliment", language_id: en_us.id, parent_id: message_tags_mt.id},
  %{
    label: "Good Bye",
    language_id: en_us.id,
    parent_id: message_tags_mt.id,
    keywords: ["bye", "byebye", "goodbye", "goodnight", "goodnite"]
  },
  %{
    label: "Greeting",
    language_id: en_us.id,
    parent_id: message_tags_mt.id,
    keywords: ["hello", "goodmorning", "hi", "hey"]
  },
  %{
    label: "Thank You",
    language_id: en_us.id,
    parent_id: message_tags_mt.id,
    keywords: ["thanks", "thankyou", "awesome", "great"]
  },

  # Status of Message
  %{label: "Critical", language_id: en_us.id, parent_id: message_tags_mt.id},
  %{label: "Important", language_id: en_us.id, parent_id: message_tags_mt.id},
  %{label: "New Contact", language_id: en_us.id, parent_id: message_tags_mt.id},
  %{label: "Not Replied", language_id: en_us.id, parent_id: message_tags_mt.id},
  %{label: "Spam", language_id: en_us.id, parent_id: message_tags_mt.id},
  %{label: "Unread", language_id: en_us.id, parent_id: message_tags_mt.id},

  # Languages
  %{
    label: "Language",
    language_id: en_us.id,
    parent_id: message_tags_mt.id,
    keywords: ["hindi", "english", "हिंदी", "अंग्रेज़ी"]
  },

  # Optout
  %{
    label: "Optout",
    language_id: en_us.id,
    parent_id: message_tags_mt.id,
    keywords: ["stop", "unsubscribe", "halt", "सदस्यता समाप्त"]
  },

  # Help
  %{
    label: "Help",
    language_id: en_us.id,
    parent_id: message_tags_mt.id,
    keywords: ["help", "मदद"]
  },

  # Tags with Value
  %{label: "Numeric", language_id: en_us.id, parent_id: message_tags_mt.id, is_value: true},

  # Tags for Sequence automation
  %{
    label: "Sequence",
    language_id: en_us.id,
    parent_id: message_tags_mt.id,
    is_value: true,
    keywords: ["start", "prev", "next", "menu"]
  },

  # Type of Contact
  %{label: "Child", language_id: en_us.id, parent_id: message_tags_ct.id},
  %{label: "Parent", language_id: en_us.id, parent_id: message_tags_ct.id},
  %{label: "Participant", language_id: en_us.id, parent_id: message_tags_ct.id},
  %{label: "User", language_id: en_us.id, parent_id: message_tags_ct.id}
]

inserted_time = DateTime.utc_now() |> DateTime.truncate(:second)

tag_entries =
  for tag_entry <- tags do
    Map.put(tag_entry, :is_reserved, true)
    |> Map.put(:inserted_at, inserted_time)
    |> Map.put(:updated_at, inserted_time)
  end

# seed multiple tags
Repo.insert_all(Tag, tag_entries)

# seed provider
provider =
  Repo.insert!(%Provider{
    name: "gupshup",
    url: "test_url_1",
    api_end_point: "test"
  })

# seed sender contact for organization
sender =
  Repo.insert!(%Contact{
    phone: "917834811114",
    name: "Glific Admin",
    language_id: en_us.id,
    last_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
  })

# seed organizatin
Repo.insert!(%Organization{
  name: "Glific",
  display_name: "Glific",
  contact_name: "Glific Admin",
  contact_id: sender.id,
  email: "glific@glific.io",
  provider_id: provider.id,
  provider_key: "random",
  provider_number: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
  default_language_id: hi.id
})

password = "secret1234"

Users.create_user(%{
  name: "Glific Admin",
  phone: "917834811114",
  password: password,
  confirm_password: password,
  roles: ["admin"]
})

# seed session templates
Repo.insert!(%SessionTemplate{
  label: "New Contact",
  body: """
  Welcome to Glific. Glific helps facilitate two way conversations. We are here to help.
  Before we start, can you please answer a few questions to set you up on our system.
  """,
  type: :text,
  shortcode: "new contact",
  is_reserved: true,
  language_id: en_us.id
})

Repo.insert!(%SessionTemplate{
  label: "New Contact",
  body: """
  ग्लिफ़िक में आपका स्वागत है

  आप किस भाषा में संदेश प्राप्त करना चाहते हैं?
  हिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें
  Type English to receive messages in English
  """,
  type: :text,
  shortcode: "new contact",
  is_reserved: true,
  language_id: hi.id
})

Repo.insert!(%SessionTemplate{
  label: "Goodbye",
  body: "Goodbye",
  type: :text,
  shortcode: "bye",
  is_reserved: true,
  language_id: en_us.id
})

Repo.insert!(%SessionTemplate{
  label: "Help",
  body: """
  Thank you for reaching out. Is this what you're looking for-
  Send 1. to see the menu,
  Send 2. to know more about Glific,
  Send 3. to know the benefits of WA for business,
  Send 4. if you'd like to be onboarded to Glific
  """,
  type: :text,
  shortcode: "help",
  is_reserved: true,
  language_id: en_us.id
})

Repo.insert!(%SessionTemplate{
  label: "Help",
  body: """
  हमे संपर्क करने के लिए धन्यवाद। क्या इसमें कुछ आपकी मदद कर सकता है-
  मेनू देखने के लिए 1. भेजें,
  ग्लिफ़िक के बारे में अधिक जानने के लिए 2. भेजें,
  व्यापार के लिए व्हाट्सएप के लाभों को जानने के लिए 3. भेजें,
  ग्लिफ़िक का उपयोग करने के लिए 4. भेजें
  """,
  type: :text,
  shortcode: "help",
  is_reserved: true,
  language_id: hi.id
})

Repo.insert!(%SessionTemplate{
  label: "Language",
  body: """
  Is <%= language %> your preferred language?

  Do you want to change the language you want to receive messages in?

  हिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें
  To receive messages in English, type English
  """,
  type: :text,
  shortcode: "language",
  is_reserved: true,
  language_id: en_us.id
})

Repo.insert!(%SessionTemplate{
  label: "Language",
  body: """
  क्या आपकी पसंदीदा भाषा <%= language %> है?

  आप जिस भाषा में संदेश प्राप्त करना चाहते हैं उसे बदल सकते हैं।

  हिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें
  To receive messages in English, type English
  """,
  type: :text,
  shortcode: "language",
  is_reserved: true,
  language_id: hi.id
})

Repo.insert!(%SessionTemplate{
  label: "Optout",
  body: """
  Your subscription is ended now.

  Type subscribe to start receiving messages again.
  """,
  type: :text,
  shortcode: "optout",
  is_reserved: true,
  language_id: en_us.id
})

Repo.insert!(%SessionTemplate{
  label: "Optout",
  body: """
  अब आपकी सदस्यता समाप्त हो गई है।

  फिर से संदेश प्राप्त करने के लिए सदस्यता टाइप करें।
  """,
  type: :text,
  shortcode: "optout",
  is_reserved: true,
  language_id: hi.id
})

Repo.insert!(%SessionTemplate{
  label: "Preferences",
  body: """
  What type of activity do you prefer
  1. Poetry
  2. Writing
  3. Story
  4. Video
  5. Done
  6. Reset my preferences
  """,
  type: :text,
  shortcode: "preference",
  is_reserved: true,
  language_id: en_us.id
})

Repo.insert!(%SessionTemplate{
  label: "Verification OTP",
  type: :text,
  shortcode: "verification",
  is_reserved: true,
  language_id: en_us.id,
  body: "Your verification OTP is: "
})

# seed hsm templates
Repo.insert!(%SessionTemplate{
  label: "HSM1",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 0,
  language_id: en_us.id,
  body:
    "I'm sorry that I wasn't able to respond to your concerns yesterday but I’m happy to assist you now. If you’d like to continue this discussion, please reply with ‘yes’"
})

Repo.insert!(%SessionTemplate{
  label: "HSM2",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "You have received a new update about {{1}}. Please click on {{2}} to know more."
})

Repo.insert!(%SessionTemplate{
  label: "HSM3",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 3,
  language_id: en_us.id,
  body: "Your {{1}} number {{2}} has been {{3}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM4",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "{{1}} is currently unavailable due to {{2}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM5",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "Please provide feedback for {{1}} by clicking on {{2}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM6",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 3,
  language_id: en_us.id,
  body: "Your {{1}} is pending. Please {{2}} by clicking on {{3}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM7",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "This is to remind you that {{1}} is due by {{2}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM8",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "You have earned {{1}} points at {{2}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM9",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "The status of {{1}} has been updated to {{2}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM10",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "You have redeemed {{1}} points on {{2}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM11",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "Your {{1}} points will expire on {{2}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM12",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "Your {{1}} is due by {{2}}. Please {{3}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM13",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "Your {{1}} is pending. Please {{2}} by clicking on {{3}}."
})

Repo.insert!(%SessionTemplate{
  label: "HSM14",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 3,
  language_id: en_us.id,
  body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}."
})

# Template for hsm with media
# Removing new line from end of heredoc
Repo.insert!(%SessionTemplate{
  label: "HSM15",
  type: :document,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: """
  Hello {{1}},

  Here is your personalized {{2}} welcome kit.\
  """
})

# Template for hsm with button
Repo.insert!(%SessionTemplate{
  label: "HSM16",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 3,
  language_id: en_us.id,
  body:
    "Download your {{1}} ticket from the link given below. | [Visit Website,https://www.gupshup.io/developer/{{1}}]"
})

# Seed saved searches
{:ok, unread} = Repo.fetch_by(Tag, %{label: "Unread"})

Repo.insert!(%SavedSearch{
  label: "All unread conversations",
  args: %{includeTags: [to_string(unread.id)]},
  is_reserved: true
})

{:ok, not_replied} = Repo.fetch_by(Tag, %{label: "Not Replied"})

Repo.insert!(%SavedSearch{
  label: "Conversations read but not replied",
  args: %{includeTags: [to_string(not_replied.id)]}
})

{:ok, optout} = Repo.fetch_by(Tag, %{label: "Optout"})

Repo.insert!(%SavedSearch{
  label: "Conversations where the contact has opted out",
  args: %{includeTags: [to_string(optout.id)]}
})

help_flow =
  Repo.insert!(%Flow{
    name: "Help Workflow",
    shortcode: "help",
    version_number: "13.1.0",
    uuid: "3fa22108-f464-41e5-81d9-d8a298854429",
    language_id: en_us.id
  })

help_flow_definition =
  File.read!("assets/flows/help.json")
  |> Jason.decode!()

help_flow_definition =
  Map.merge(help_flow_definition, %{
    "name" => help_flow.name,
    "uuid" => help_flow.uuid
  })

Repo.insert!(%FlowRevision{
  definition: help_flow_definition,
  flow_id: help_flow.id
})

language_flow =
  Repo.insert!(%Flow{
    name: "Language Workflow",
    shortcode: "language",
    version_number: "13.1.0",
    uuid: "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf",
    language_id: en_us.id
  })

language_flow_definition =
  File.read!("assets/flows/language.json")
  |> Jason.decode!()

language_flow_definition =
  Map.merge(language_flow_definition, %{
    "name" => language_flow.name,
    "uuid" => language_flow.uuid
  })

Repo.insert!(%FlowRevision{
  definition: language_flow_definition,
  flow_id: language_flow.id
})

preferences_flow =
  Repo.insert!(%Flow{
    name: "Preferences Workflow",
    shortcode: "preference",
    version_number: "13.1.0",
    uuid: "63397051-789d-418d-9388-2ef7eb1268bb",
    language_id: en_us.id
  })

preferences_flow_definition =
  File.read!("assets/flows/preference.json")
  |> Jason.decode!()

preferences_flow_definition =
  Map.merge(preferences_flow_definition, %{
    "name" => preferences_flow.name,
    "uuid" => preferences_flow.uuid
  })

Repo.insert!(%FlowRevision{
  definition: preferences_flow_definition,
  flow_id: preferences_flow.id
})

new_contact_flow =
  Repo.insert!(%Flow{
    name: "New_Contact Workflow",
    shortcode: "new contact",
    version_number: "13.1.0",
    uuid: "973a24ea-dd2e-4d19-a427-83b0620161b0",
    language_id: en_us.id
  })

new_contact_flow_definition =
  File.read!("assets/flows/new_contact.json")
  |> Jason.decode!()

new_contact_flow_definition =
  Map.merge(new_contact_flow_definition, %{
    "name" => new_contact_flow.name,
    "uuid" => new_contact_flow.uuid
  })

Repo.insert!(%FlowRevision{
  definition: new_contact_flow_definition,
  flow_id: new_contact_flow.id
})
