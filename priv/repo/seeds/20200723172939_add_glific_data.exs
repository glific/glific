defmodule Glific.Repo.Seeds.AddGlificData do
  use Glific.Seed

  envs([:dev, :test, :prod])

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

  @now DateTime.utc_now() |> DateTime.truncate(:second)
  @password "secret1234"
  @admin_phone "917834811114"

  def up(_repo) do
    languages = languages()

    gtags(languages)

    provider = providers()

    admin = contacts(languages)

    organization(admin, provider, languages)

    users()

    hsm_templates(languages)

    saved_searches()

    flows(languages)
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
    message_tags_mt = Repo.insert!(%Tag{label: "Messages", is_reserved: true, language: en_us})
    message_tags_ct = Repo.insert!(%Tag{label: "Contacts", is_reserved: true, language: en_us})

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

      # Type of Contact
      %{label: "Child", language_id: en_us.id, parent_id: message_tags_ct.id},
      %{label: "Parent", language_id: en_us.id, parent_id: message_tags_ct.id},
      %{label: "Participant", language_id: en_us.id, parent_id: message_tags_ct.id},
      %{label: "Staff", language_id: en_us.id, parent_id: message_tags_ct.id}
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

  def users do
    Users.create_user(%{
      name: "Glific Admin",
      phone: @admin_phone,
      password: @password,
      confirm_password: @password,
      roles: ["admin"]
    })
  end

  def hsm_templates(languages) do
    {_hi, en_us} = languages

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
  end

  def saved_searches do
    labels = Repo.label_id_map(Tag, ["Unread", "Not Replied", "Optout"])

    Repo.insert!(%SavedSearch{
      label: "All unread conversations",
      args: %{includeTags: [to_string(labels["Unread"])]},
      is_reserved: true
    })

    Repo.insert!(%SavedSearch{
      label: "Conversations read but not replied",
      args: %{includeTags: [to_string(labels["Not Replied"])]},
      is_reserved: true
    })

    Repo.insert!(%SavedSearch{
      label: "Conversations where the contact has opted out",
      args: %{includeTags: [to_string(labels["Optout"])]},
      is_reserved: true
    })
  end

  def flows(languages) do
    {_hi, en_us} = languages

    data = [
      {"Help Workflow", "help", "3fa22108-f464-41e5-81d9-d8a298854429", "help.json"},
      {"Language Workflow", "language", "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf", "language.json"},
      {"Preferences Workflow", "preference", "63397051-789d-418d-9388-2ef7eb1268bb",
       "preference.json"},
      {"New Contact Workflow", "new contact", "973a24ea-dd2e-4d19-a427-83b0620161b0",
       "new_contact.json"},
      {"Registration Workflow", "registration", "5e086708-37b2-4b20-80c2-bdc0f213c3c6",
       "registration.json"}
    ]

    Enum.map(data, fn f -> flow(f, en_us) end)
  end

  defp flow(data, language) do
    f =
      Repo.insert!(%Flow{
        name: elem(data, 0),
        shortcode: elem(data, 1),
        version_number: "13.1.0",
        uuid: elem(data, 2),
        language: language
      })

    definition =
      File.read!("assets/flows/" <> elem(data, 3))
      |> Jason.decode!()
      |> Map.merge(%{
        "name" => f.name,
        "uuid" => f.uuid,
        "language" => language.label_locale
      })

    Repo.insert(%FlowRevision{
      definition: definition,
      flow_id: f.id
    })
  end
end
