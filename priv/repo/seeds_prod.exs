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
  Partners.Organization,
  Partners.Provider,
  Repo,
  Searches.SavedSearch,
  Settings.Language,
  Tags.Tag,
  Templates.SessionTemplate,
  Users,
}

# seed languages
hi = Repo.insert!(%Language{label: "Hindi", label_locale: "हिंदी", locale: "hi"})
en_us = Repo.insert!(%Language{label: "English (United States)", label_locale: "English", locale: "en_US"})

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
provider = Repo.insert!(%Provider{
  name: "gupshup",
  url: "test_url_1",
  api_end_point: "test"
})

# Sender Contact for organization
sender =
  Repo.insert!(%Contact{
    phone: "917834811114",
    name: "Glific Admin",
    language_id: en_us.id,
    last_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
  })

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

Repo.insert!(%SessionTemplate{
  label: "New Contact",
  body: """
  Welcome to Glific.

  What language do you want to receive messages in?
  हिंदी के लिए 1 दबाएँहिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें
  Type English to receive messages in English
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

for label <- ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"] do
  Repo.insert!(%SessionTemplate{
    label: label,
    type: :text,
    shortcode: String.downcase(label),
    is_reserved: false,
    language_id: hi.id,
    body: """
    इस संदेश की सामग्री संख्यात्मक मूल्य का प्रतिनिधित्व करने के लिए विशिष्ट होगी: #{label}.
    जंगली जाओ !, अपनी बात करो। मैं सिर्फ एक स्क्रिप्ट हूं
    """
  })

  Repo.insert!(%SessionTemplate{
    label: label,
    type: :text,
    shortcode: String.downcase(label),
    is_reserved: false,
    language_id: en_us.id,
    body: """
    Contents of this message will be specific to the numeric value representing: #{label}.
    Go wild!, Do your own thing. I am just a script
    """
  })
end

Repo.insert!(%SessionTemplate{
  label: "Start of Sequence",
  type: :text,
  shortcode: "start",
  is_reserved: false,
  language_id: hi.id,
  body: """
  This is the start of a pre-determined sequence.
  """
})

Repo.insert!(%SessionTemplate{
  label: "Start of Sequence",
  type: :text,
  shortcode: "start",
  is_reserved: false,
  language_id: en_us.id,
  body: """
  This is the start of a pre-determined sequence
  """
})

Repo.insert!(%SessionTemplate{
  label: "Menu",
  type: :text,
  shortcode: "menu",
  is_reserved: false,
  language_id: hi.id,
  body: """
  Type one of the below:

  next - next item in sequence
  prev - prev item in sequence
  start - start (or restart) the sequence
  menu - show this menu
  """
})

Repo.insert!(%SessionTemplate{
  label: "Menu",
  type: :text,
  shortcode: "menu",
  is_reserved: false,
  language_id: en_us.id,
  body: """
  Type one of the below:

  next - next item in sequence
  prev - prev item in sequence
  start - start (or restart) the sequence
  menu - show this menu
  """
})

Repo.insert!(%SessionTemplate{
  label: "HSM1",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 0,
  language_id: en_us.id,
  body: """
  I'm sorry that I wasn't able to respond to your concerns yesterday but I’m happy to assist you now. If you’d like to continue this discussion, please reply with ‘yes’
  """
})

Repo.insert!(%SessionTemplate{
  label: "HSM2",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 4,
  language_id: en_us.id,
  body: """
  Please find your {{1}} ticket for {{2}} on {{3}}. Please click on {{4}} to get a printout.
  """
})

Repo.insert!(%SessionTemplate{
  label: "HSM3",
  type: :text,
  shortcode: "hsm",
  is_hsm: true,
  number_parameters: 2,
  language_id: en_us.id,
  body: """
  Your {{1}} points will expire on {{2}}.
  """
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
