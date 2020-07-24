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

  # Status of outbound Message
  %{label: "Not Responded", language_id: en_us.id, parent_id: message_tags_mt.id},

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
  %{label: "Staff", language_id: en_us.id, parent_id: message_tags_ct.id}
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
  language_id: en_us.id,
  uuid: "5d7346d5-347c-4eca-b422-f05b07c41820"
})

Repo.insert!(%SessionTemplate{
  label: "New Contact",
  body: """
  ग्लिफ़िक में आपका स्वागत है
  """,
  type: :text,
  shortcode: "new contact",
  is_reserved: true,
  language_id: hi.id,
  uuid: "38c74fcc-f586-4aef-a367-70a7c4c72a1d"
})

Repo.insert!(%SessionTemplate{
  label: "Goodbye",
  body: "Goodbye",
  type: :text,
  shortcode: "bye",
  is_reserved: true,
  language_id: en_us.id,
  uuid: "bb190315-ce63-4e9a-88de-2e7da691f118"
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
  language_id: en_us.id,
  uuid: "2f1c9eee-cb81-4624-8d18-9b21ff0bb2e6"
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
  language_id: hi.id,
  uuid: "ea83bdcd-a940-49c2-b9cb-1194f75fffd9"
})

Repo.insert!(%SessionTemplate{
  label: "Language",
  body: """
  Your language is currently set at {{1}}

  Do you want to change the language you want to receive messages in?

  हिंदी में संदेश प्राप्त करने के लिए 1 टाइप करें
  To continue to receive messages in English, type 2
  """,
  type: :text,
  shortcode: "language",
  is_reserved: true,
  language_id: en_us.id,
  uuid: "942cb24b-5c78-4c7f-a3f9-1b4d1ba63118",
  number_parameters: 1
})

Repo.insert!(%SessionTemplate{
  label: "Language",
  body: """
  आपकी भाषा वर्तमान में सेट हैा {{1}}

  आप जिस भाषा में संदेश प्राप्त करना चाहते हैं उसे बदल सकते हैं।क्या आप उस भाषा को बदलना चाहते हैं जिसमें आप संदेश प्राप्त करना चाहते हैं?

  हिंदी में संदेश प्राप्त करने के लिए 1 टाइप करें
  To receive messages in English, type 2
  """,
  type: :text,
  shortcode: "language",
  is_reserved: true,
  language_id: hi.id,
  uuid: "af0caab8-796d-4591-bd7f-7aed57e1ce81",
  number_parameters: 1
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
  language_id: en_us.id,
  uuid: "754eebd8-67b6-4fdc-bf0a-a81a0bf16f8c"
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
  language_id: hi.id,
  uuid: "d36c2204-fc6f-4301-b3ef-a3aedfd10215"
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
  language_id: en_us.id,
  uuid: "a9834b33-583d-471b-aa50-bdf0a4c8c34b"
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
    "I'm sorry that I wasn't able to respond to your concerns yesterday but I’m happy to assist you now. If you’d like to continue this discussion, please reply with ‘yes’",
  uuid: "9381b1b9-1b9b-45a6-81f4-f91306959619"
})

Repo.insert!(%SessionTemplate{
  label: "HSM2",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "You have received a new update about {{1}}. Please click on {{2}} to know more.",
  uuid: "8f614010-a48e-4d97-88cd-3a577471f60c"
})

Repo.insert!(%SessionTemplate{
  label: "HSM3",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 3,
  language_id: en_us.id,
  body: "Your {{1}} number {{2}} has been {{3}}.",
  uuid: "c39f98e7-9b32-4554-a5b2-2bcc9a297053"
})

Repo.insert!(%SessionTemplate{
  label: "HSM4",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "{{1}} is currently unavailable due to {{2}}.",
  uuid: "70ddb61b-ee8d-400e-8190-0c9df4642774"
})

Repo.insert!(%SessionTemplate{
  label: "HSM5",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "Please provide feedback for {{1}} by clicking on {{2}}.",
  uuid: "fe9cad7b-2324-4526-a810-2ccf03b1cbd1"
})

Repo.insert!(%SessionTemplate{
  label: "HSM6",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 3,
  language_id: en_us.id,
  body: "Your {{1}} is pending. Please {{2}} by clicking on {{3}}.",
  uuid: "bb498fb8-e37d-4d4f-bc8a-b97d1a02e60d"
})

Repo.insert!(%SessionTemplate{
  label: "HSM7",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "This is to remind you that {{1}} is due by {{2}}.",
  uuid: "b5f0d185-999f-411a-97bd-2f0876e5b831"
})

Repo.insert!(%SessionTemplate{
  label: "HSM8",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "You have earned {{1}} points at {{2}}.",
  uuid: "72b380e8-add3-4981-a454-287d349763b2"
})

Repo.insert!(%SessionTemplate{
  label: "HSM9",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "The status of {{1}} has been updated to {{2}}.",
  uuid: "f8bded9a-7f4b-46b9-b009-3efc6bd67904"
})

Repo.insert!(%SessionTemplate{
  label: "HSM10",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "You have redeemed {{1}} points on {{2}}.",
  uuid: "0c863528-427c-4345-8bb1-2c4ec29506ea"
})

Repo.insert!(%SessionTemplate{
  label: "HSM11",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "Your {{1}} points will expire on {{2}}.",
  uuid: "8ac4ecda-851e-4f1f-aa29-ca5366bf7a2a"
})

Repo.insert!(%SessionTemplate{
  label: "HSM12",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "Your {{1}} is due by {{2}}. Please {{3}}.",
  uuid: "6c194aa2-f77f-4f9a-8a83-1a63e39c49e2"
})

Repo.insert!(%SessionTemplate{
  label: "HSM13",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: "Your {{1}} is pending. Please {{2}} by clicking on {{3}}.",
  uuid: "a2a643d6-c805-4ccd-896e-c74c7da2e08e"
})

Repo.insert!(%SessionTemplate{
  label: "HSM14",
  type: :text,
  shortcode: "otp_verification",
  is_hsm: true,
  number_parameters: 3,
  language_id: en_us.id,
  body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
  uuid: "e55f2c10-541c-470b-a5ff-9249ae82bc95"
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
  """,
  uuid: "e89b3d89-c7c0-4c87-bf04-f70c51ade5a5"
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
    "Download your {{1}} ticket from the link given below. | [Visit Website,https://www.gupshup.io/developer/{{1}}]",
  uuid: "ae35ef89-ea4b-4b04-979d-04e7538f52dc"
})

# Seed saved searches
{:ok, unread} = Repo.fetch_by(Tag, %{label: "Unread"})

Repo.insert!(%SavedSearch{
  label: "All unread conversations",
  args: %{
    filter: %{includeTags: [to_string(unread.id)]},
    contactOpts: %{limit: 10},
    messageOpts: %{limit: 5},
    term: ""
  },
  is_reserved: true
})

{:ok, not_replied} = Repo.fetch_by(Tag, %{label: "Not Replied"})

Repo.insert!(%SavedSearch{
  label: "Conversations read but not replied",
  args: %{
    filter: %{includeTags: [to_string(not_replied.id)]},
    contactOpts: %{limit: 10},
    messageOpts: %{limit: 5},
    term: ""
  }
})

{:ok, not_responded} = Repo.fetch_by(Tag, %{label: "Not Responded"})

Repo.insert!(%SavedSearch{
  label: "Conversations read but not responded",
  args: %{
    filter: %{includeTags: [to_string(not_responded.id)]},
    contactOpts: %{limit: 10},
    messageOpts: %{limit: 5},
    term: ""
  }
})

{:ok, optout} = Repo.fetch_by(Tag, %{label: "Optout"})

Repo.insert!(%SavedSearch{
  label: "Conversations where the contact has opted out",
  args: %{
    filter: %{includeTags: [to_string(optout.id)]},
    contactOpts: %{limit: 10},
    messageOpts: %{limit: 5},
    term: ""
  }
})

help_flow =
  Repo.insert!(%Flow{
    name: "Help Workflow",
    shortcode: "help",
    version_number: "13.1.0",
    uuid: "3fa22108-f464-41e5-81d9-d8a298854429"
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
    uuid: "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf"
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
    uuid: "63397051-789d-418d-9388-2ef7eb1268bb"
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
    uuid: "973a24ea-dd2e-4d19-a427-83b0620161b0"
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

registration_flow =
  Repo.insert!(%Flow{
    name: "Registration Workflow",
    shortcode: "registration",
    version_number: "13.1.0",
    uuid: "5e086708-37b2-4b20-80c2-bdc0f213c3c6"
  })

registration_flow_definition =
  File.read!("assets/flows/registration.json")
  |> Jason.decode!()

registration_flow_definition =
  Map.merge(registration_flow_definition, %{
    "name" => registration_flow.name,
    "uuid" => registration_flow.uuid
  })

Repo.insert!(%FlowRevision{
  definition: registration_flow_definition,
  flow_id: registration_flow.id
})
