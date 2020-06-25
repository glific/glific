defmodule Glific.Seeds do
  @moduledoc """
  Script for populating the database. We can call this from tests and/or /priv/repo
  """
  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Messages.MessageMedia,
    Partners.Organization,
    Partners.Provider,
    Repo,
    Settings,
    Settings.Language,
    Tags.Tag,
    Templates.SessionTemplate
  }

  @doc """
  Smaller functions to seed various tables. This allows the test functions to call specific seeder functions.
  In the next phase we will also add unseeder functions as we learn more of the test capabilities
  """
  @spec seed_language() :: {Language.t(), Language.t()}
  def seed_language do
    {
      Repo.insert!(%Language{label: "Hindi", label_locale: "हिंदी", locale: "hi_IN"}),
      Repo.insert!(%Language{
        label: "English (United States)",
        label_locale: "English",
        locale: "en_US"
      })
    }
  end

  @doc false
  @spec seed_tag({Language.t(), Language.t()}) :: nil
  def seed_tag({hi_in, en_us}) do
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

      # Tags with Value
      %{label: "Numeric", language_id: en_us.id, parent_id: message_tags_mt.id, is_value: true},

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

    # seed tags
    Repo.insert_all(Tag, tag_entries)

    Repo.insert!(%Tag{label: "This is for testing", language: en_us})
    Repo.insert!(%Tag{label: "यह परीक्षण के लिए है", language: hi_in})
  end

  @doc false
  @spec seed_contacts :: {integer(), nil}
  def seed_contacts do
    [hindi | _] = Settings.list_languages(%{label: "hindi"})
    [english | _] = Settings.list_languages(%{label: "english"})

    contacts = [
      %{phone: "917834811231", name: "Default receiver", language_id: hindi.id},
      %{
        name: "Adelle Cavin",
        phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
        language_id: hindi.id
      },
      %{
        name: "Margarita Quinteros",
        phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
        language_id: hindi.id
      },
      %{
        name: "Chrissy Cron",
        phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
        language_id: english.id
      },
      %{
        name: "Hailey Wardlaw",
        phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
        language_id: english.id
      }
    ]

    inserted_time = DateTime.utc_now() |> DateTime.truncate(:second)

    contact_entries =
      for contact_entry <- contacts do
        contact_entry
        |> Map.put(:inserted_at, inserted_time)
        |> Map.put(:updated_at, inserted_time)
      end

    # seed contacts
    Repo.insert_all(Contact, contact_entries)
  end

  @doc false
  @spec seed_providers :: Provider.t()
  def seed_providers do
    default_provider =
      Repo.insert!(%Provider{
        name: "Default Provider",
        url: "test_url",
        api_end_point: "test"
      })

    Repo.insert!(%Provider{
      name: "gupshup",
      url: "test_url_1",
      api_end_point: "test"
    })

    Repo.insert!(%Provider{
      name: "twilio",
      url: "test_url_2",
      api_end_point: "test"
    })

    default_provider
  end

  @doc false
  @spec seed_organizations(Provider.t(), {Language.t(), Language.t()}) :: nil
  def seed_organizations(default_provider, {_hi_in, en_us}) do
    # Sender Contact for organization
    sender =
      Repo.insert!(%Contact{
        phone: "91783481111",
        name: "Default Sender",
        language_id: en_us.id
      })

    Repo.insert!(%Organization{
      name: "Default Organization",
      display_name: "Default Organization",
      contact_name: "Test",
      contact_id: sender.id,
      email: "test@glific.org",
      provider_id: default_provider.id,
      provider_key: "random",
      provider_number: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
      default_language_id: en_us.id
    })

    Repo.insert!(%Organization{
      name: "Slam Out Loud",
      display_name: "Slam Out Loud",
      contact_name: "Jigyasa and Gaurav",
      email: "jigyasa@glific.org",
      provider_id: default_provider.id,
      provider_key: "random",
      provider_number: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
      default_language_id: en_us.id
    })
  end

  @doc false
  @spec seed_messages :: nil
  def seed_messages do
    {:ok, sender} = Repo.fetch_by(Contact, %{name: "Default Sender"})
    {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Default receiver"})

    Repo.insert!(%Message{
      body: "Default message body",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: "ZZZ message body for order test",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: "hindi",
      flow: :outbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: "english",
      flow: :outbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: "hola",
      flow: :outbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })
  end

  @doc false
  @spec seed_messages_media :: nil
  def seed_messages_media do
    Repo.insert!(%MessageMedia{
      url: Faker.Avatar.image_url(),
      source_url: Faker.Avatar.image_url(),
      thumbnail: Faker.Avatar.image_url(),
      caption: "default caption",
      provider_media_id: Faker.String.base64(10)
    })

    Repo.insert!(%MessageMedia{
      url: Faker.Avatar.image_url(),
      source_url: Faker.Avatar.image_url(),
      thumbnail: Faker.Avatar.image_url(),
      caption: Faker.String.base64(10),
      provider_media_id: Faker.String.base64(10)
    })

    Repo.insert!(%MessageMedia{
      url: Faker.Avatar.image_url(),
      source_url: Faker.Avatar.image_url(),
      thumbnail: Faker.Avatar.image_url(),
      caption: Faker.String.base64(10),
      provider_media_id: Faker.String.base64(10)
    })

    Repo.insert!(%MessageMedia{
      url: Faker.Avatar.image_url(),
      source_url: Faker.Avatar.image_url(),
      thumbnail: Faker.Avatar.image_url(),
      caption: Faker.String.base64(10),
      provider_media_id: Faker.String.base64(10)
    })
  end

  @doc false
  @spec seed_session_templates({Language.t(), Language.t()}) :: nil
  def seed_session_templates({hi_in, en_us}) do
    session_template_parent =
      Repo.insert!(%SessionTemplate{
        label: "Default Template Label",
        body: "Default Template",
        type: :text,
        language_id: en_us.id
      })

    Repo.insert!(%SessionTemplate{
      label: "Another Template Label",
      body: "Another Template",
      type: :text,
      language_id: en_us.id,
      parent_id: session_template_parent.id
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
      language_id: hi_in.id
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
      body: "Here we will enter some help text",
      type: :text,
      shortcode: "help",
      is_reserved: true,
      language_id: en_us.id
    })

    Repo.insert!(%SessionTemplate{
      label: "Help (Hindi)",
      body: "भाषा बदलने के लिए, 1. दबाएँ मेनू देखने के लिए, 2 दबाएँ",
      type: :text,
      shortcode: "",
      is_reserved: true,
      language_id: hi_in.id
    })

    Repo.insert!(%SessionTemplate{
      label: "Language",
      body: """
      Your preferred language is <%= language %>

      Do you want to change the language you want to receive messages in?

      हिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें
      Type English to receive messages in English
      """,
      type: :text,
      shortcode: "language",
      is_reserved: true,
      language_id: en_us.id
    })

    Repo.insert!(%SessionTemplate{
      label: "Language",
      body: """
      आपकी पसंदीदा भाषा <%= language %> है

      आप किस भाषा में संदेश प्राप्त करना चाहते हैं?क्या आप उस भाषा को बदलना चाहते हैं जिसमें आप संदेश प्राप्त करना चाहते हैं?

      हिंदी में संदेश प्राप्त करने के लिए हिंदी टाइप करें
      Type English to receive messages in English
      """,
      type: :text,
      shortcode: "language",
      is_reserved: true,
      language_id: hi_in.id
    })
  end

  @doc """
  Function to populate some basic data that we need for the system to operate. We will
  split this function up into multiple different ones for test, dev and production
  """
  @spec seed :: nil
  def seed do
    lang = seed_language()

    default_provider = seed_providers()

    seed_organizations(default_provider, lang)

    seed_contacts()

    seed_session_templates(lang)

    seed_tag(lang)

    seed_messages()

    seed_messages_media()
  end
end
