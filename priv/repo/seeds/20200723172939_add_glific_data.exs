defmodule Glific.Repo.Seeds.AddGlificData do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Contacts,
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

  @now DateTime.utc_now() |> DateTime.truncate(:second)
  @password "secret1234"
  @admin_phone "917834811114"

  def up(_repo) do
    languages = languages()

    gtags(languages)

    provider = providers()

    admin = contacts(languages)

    organization(admin, provider, languages)

    users(admin)

    hsm_templates(languages)

    saved_searches()

    flows()

    opted_in_contacts()
  end

  def down(_repo) do
    # this is the first migration, so all tables are empty
    # hence we can get away with truncating in reverse order
    # DO NOT FOLLOW this pattern for any other migrations
    truncates = [
      "TRUNCATE flows;",
      "TRUNCATE flow_revisions;",
      "TRUNCATE saved_searches;",
      "TRUNCATE session_templates;",
      "TRUNCATE users;",
      "TRUNCATE organizations;",
      "TRUNCATE contacts;",
      "TRUNCATE providers;",
      "TRUNCATE tags;",
      "TRUNCATE languages;"
    ]

    Enum.each(truncates, fn t -> Repo.query(t) end)
  end

  def languages do
    hi = Repo.insert!(%Language{label: "Hindi", label_locale: "हिंदी", locale: "hi"})

    en_us =
      Repo.insert!(%Language{
        label: "English (United States)",
        label_locale: "English",
        locale: "en_US"
      })

    {hi, en_us}
  end

  def gtags(languages) do
    {_hi, en_us} = languages

    # seed tags
    message_tags_mt =
      Repo.insert!(%Tag{
        label: "Messages",
        shortcode: "messages",
        is_reserved: true,
        language: en_us
      })

    message_tags_ct =
      Repo.insert!(%Tag{
        label: "Contacts",
        shortcode: "contacts",
        is_reserved: true,
        language: en_us
      })

    tags = [
      # Intent of message
      %{
        label: "Good Bye",
        shortcode: "goodbye",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        keywords: ["bye", "byebye", "goodbye", "goodnight", "goodnite"]
      },
      %{
        label: "Greeting",
        shortcode: "greeting",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        keywords: ["hello", "goodmorning", "hi", "hey"]
      },
      %{
        label: "Thank You",
        shortcode: "thankyou",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        keywords: ["thanks", "thankyou", "awesome", "great"]
      },

      # Status of Message
      %{
        label: "Important",
        shortcode: "important",
        language_id: en_us.id,
        parent_id: message_tags_mt.id
      },
      %{
        label: "New Contact",
        shortcode: "newcontact",
        language_id: en_us.id,
        parent_id: message_tags_mt.id
      },
      %{
        label: "Not replied",
        shortcode: "notreplied",
        language_id: en_us.id,
        parent_id: message_tags_mt.id
      },
      %{label: "Spam", shortcode: "spam", language_id: en_us.id, parent_id: message_tags_mt.id},
      %{
        label: "Unread",
        shortcode: "unread",
        language_id: en_us.id,
        parent_id: message_tags_mt.id
      },

      # Status of outbound Message
      %{
        label: "Not Responded",
        shortcode: "notresponded",
        language_id: en_us.id,
        parent_id: message_tags_mt.id
      },

      # Languages
      %{
        label: "Language",
        shortcode: "language",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        keywords: ["hindi", "english", "हिंदी", "अंग्रेज़ी"]
      },

      # Optout
      %{
        label: "Optout",
        shortcode: "optout",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        keywords: ["stop", "unsubscribe", "halt", "सदस्यता समाप्त"]
      },

      # Help
      %{
        label: "Help",
        shortcode: "help",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        keywords: ["help", "मदद"]
      },

      # Tags with Value
      %{
        label: "Numeric",
        shortcode: "numeric",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        is_value: true
      },

      # Type of Contact
      %{label: "Child", shortcode: "child", language_id: en_us.id, parent_id: message_tags_ct.id},
      %{
        label: "Parent",
        shortcode: "parent",
        language_id: en_us.id,
        parent_id: message_tags_ct.id
      },
      %{
        label: "Participant",
        shortcode: "participant",
        language_id: en_us.id,
        parent_id: message_tags_ct.id
      },
      %{label: "Staff", shortcode: "staff", language_id: en_us.id, parent_id: message_tags_ct.id}
    ]

    tags =
      Enum.map(
        tags,
        fn tag ->
          tag
          |> Map.put(:is_reserved, true)
          |> Map.put(:inserted_at, @now)
          |> Map.put(:updated_at, @now)
        end
      )

    # seed multiple tags
    Repo.insert_all(Tag, tags)
  end

  def providers do
    Repo.insert!(%Provider{
      name: "Gupshup",
      url: "https://gupshup.io/",
      api_end_point: "https://api.gupshup.io/sm/api/v1"
    })
  end

  def contacts(languages) do
    {_hi, en_us} = languages

    Repo.insert!(%Contact{
      phone: @admin_phone,
      name: "Glific Admin",
      language_id: en_us.id,
      last_message_at: @now
    })
  end

  def organization(admin, provider, languages) do
    {_hi, en_us} = languages

    Repo.insert!(%Organization{
      name: "Glific",
      display_name: "Glific",
      contact_name: "Glific Admin",
      contact_id: admin.id,
      email: "ADMIN@REPLACE_ME.NOW",
      provider_id: provider.id,
      provider_key: "ADD_PROVIDER_API_KEY",
      provider_number: "ADD_MY_PHONE_NUMBER",
      default_language_id: en_us.id
    })
  end

  def users(admin) do
    Users.create_user(%{
      name: "Glific Admin",
      phone: @admin_phone,
      password: @password,
      confirm_password: @password,
      roles: ["admin"],
      contact_id: admin.id
    })
  end

  def hsm_templates(languages) do
    {hi, en_us} = languages

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

    Repo.insert!(%SessionTemplate{
      label: "Missed Message Apology",
      type: :text,
      shortcode: "missed_message",
      is_hsm: true,
      number_parameters: 0,
      language_id: en_us.id,
      body: """
      I'm sorry that I wasn't able to respond to your concerns yesterday but I’m happy to assist you now.
      If you’d like to continue this discussion, please reply with ‘yes’
      """,
      uuid: "9381b1b9-1b9b-45a6-81f4-f91306959619"
    })

    Repo.insert!(%SessionTemplate{
      label: "OTP Message",
      type: :text,
      shortcode: "otp",
      is_hsm: true,
      number_parameters: 3,
      language_id: en_us.id,
      body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
      uuid: "e55f2c10-541c-470b-a5ff-9249ae82bc95"
    })

    Repo.insert!(%SessionTemplate{
      label: "User Regitstration",
      body: """
      Please click on the link to register with the phone number @contact.phone
      @global.registration.url
      """,
      type: :text,
      shortcode: "user-registration",
      is_reserved: true,
      language_id: en_us.id,
      uuid: "fbf8d5a6-91ab-47ab-9691-35ef35443ad8"
    })
  end

  def saved_searches do
    labels = Repo.label_id_map(Tag, ["Not replied", "Not Responded", "Optout", "Unread"])

    data = [
      {"All conversations", "All"},
      {"All unread conversations", "Unread"},
      {"Conversations read but not replied", "Not replied"},
      {"Conversations where the contact has opted out", "Optout"},
      {"Conversations read but not responded", "Not Responded"}
    ]

    Enum.each(data, &saved_search(&1, labels))
  end

  defp saved_search({label, shortcode}, _labels) when shortcode == "All",
    do:
      Repo.insert!(%SavedSearch{
        label: label,
        shortcode: shortcode,
        args: %{
          filter: %{term: ""},
          contactOpts: %{limit: 20, offset: 0},
          messageOpts: %{limit: 10, offset: 0}
        },
        is_reserved: true
      })

  defp saved_search({label, shortcode}, labels),
    do:
      Repo.insert!(%SavedSearch{
        label: label,
        shortcode: shortcode,
        args: %{
          filter: %{includeTags: [to_string(labels[shortcode])], term: ""},
          contactOpts: %{limit: 20, offset: 0},
          messageOpts: %{limit: 10, offset: 0}
        },
        is_reserved: true
      })

  def flows() do
    data = [
      {"Help Workflow", "help", ["help", "मदद"], "3fa22108-f464-41e5-81d9-d8a298854429",
       "help.json"},
      {"Language Workflow", "language", ["language", "भाषा"],
       "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf", "language.json"},
      {"Preferences Workflow", "preference", ["preference"],
       "63397051-789d-418d-9388-2ef7eb1268bb", "preference.json"},
      {"New Contact Workflow", "newcontact", ["newcontact"],
       "6fe8fda9-2df6-4694-9fd6-45b9e724f545", "new_contact.json"},
      {"Registration Workflow", "registration", ["registration"],
       "f4f38e00-3a50-4892-99ce-a281fe24d040", "registration.json"},
      {"Out of Office Workflow", "outofoffice", ["outofoffice"],
       "af8a0aaa-dd10-4eee-b3b8-e59530e2f5f7", "out_of_office.json"}
    ]

    Enum.map(data, &flow(&1))
  end

  defp flow({name, shortcode, keywords, uuid, file}) do
    f =
      Repo.insert!(%Flow{
        name: name,
        shortcode: shortcode,
        keywords: keywords,
        version_number: "13.1.0",
        uuid: uuid
      })

    definition =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/" <> file))
      |> Jason.decode!()
      |> Map.merge(%{
        "name" => f.name,
        "uuid" => f.uuid
      })

    Repo.insert(%FlowRevision{
      definition: definition,
      flow_id: f.id
    })
  end

  def opted_in_contacts do
    with {:ok, url} <- Application.fetch_env(:glific, :provider_optin_list_url),
         {:ok, api_key} <- Application.fetch_env(:glific, :provider_key),
         {:ok, response} <- HTTPoison.get(url, [{"apikey", api_key}]),
         {:ok, response_data} <- Poison.decode(response.body),
         false <- is_nil(response_data["users"]) do
      users = response_data["users"]

      Enum.each(users, fn user ->
        {:ok, last_message_at} = DateTime.from_unix(user["lastMessageTimeStamp"], :millisecond)
        {:ok, optin_time} = DateTime.from_unix(user["optinTimeStamp"], :millisecond)

        phone = user["countryCode"] <> user["phoneCode"]

        Contacts.upsert(%{
          phone: phone,
          last_message_at: last_message_at |> DateTime.truncate(:second),
          optin_time: optin_time |> DateTime.truncate(:second),
          provider_status: check_provider_status(last_message_at)
        })
      end)
    end
  end

  defp check_provider_status(last_message_at) do
    if Timex.diff(DateTime.utc_now(), last_message_at, :hours) < 24 do
      :session_and_hsm
    else
      :hsm
    end
  end
end
