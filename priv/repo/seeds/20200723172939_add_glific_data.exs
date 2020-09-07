defmodule Glific.Repo.Seeds.AddGlificData do
  use Glific.Seeds.Seed
  import Ecto.Changeset, only: [change: 2]

  envs([:dev, :test, :prod])

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactsField,
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

    provider = providers()

    organization = organization(provider, languages)

    # calling it gtags, since tags is a macro in philcolumns
    gtags(organization, languages)

    admin = contacts(organization, languages)

    users(admin, organization)

    hsm_templates(organization, languages)

    saved_searches(organization)

    flows(organization)

    opted_in_contacts(organization)

    contacts_field(organization)
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
      "TRUNCATE languages;",
      "TRUNCATE contacts_fields;"
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

    _ta =
      Repo.insert!(%Language{
        label: "Tamil",
        label_locale: "தமிழ்",
        locale: "ta"
      })

    {hi, en_us}
  end

  def gtags(organization, languages) do
    {_hi, en_us} = languages

    # seed tags
    message_tags_mt =
      Repo.insert!(%Tag{
        label: "Messages",
        shortcode: "messages",
        description: "A default message tag",
        is_reserved: true,
        language_id: en_us.id,
        organization_id: organization.id
      })

    message_tags_ct =
      Repo.insert!(%Tag{
        label: "Contacts",
        shortcode: "contacts",
        description: "A contact tag for users that are marked as contacts",
        is_reserved: true,
        language_id: en_us.id,
        organization_id: organization.id
      })

    tags = [
      # Intent of message
      %{
        label: "Good Bye",
        shortcode: "goodbye",
        description:
          "Marking message as good wishes when parting or at the end of a conversation",
        parent_id: message_tags_mt.id,
        keywords: ["bye", "byebye", "goodbye", "goodnight", "goodnite"]
      },
      %{
        label: "Greeting",
        shortcode: "greeting",
        parent_id: message_tags_mt.id,
        description: "Marking message as a sign of welcome",
        keywords: ["hello", "goodmorning", "hi", "hey"]
      },
      %{
        label: "Thank You",
        shortcode: "thankyou",
        description: "Marking message as a expression of thanks",
        parent_id: message_tags_mt.id,
        keywords: ["thanks", "thankyou", "awesome", "great"]
      },

      # Status of Message
      %{
        label: "Important",
        shortcode: "important",
        description: "Marking message as of great significance or value",
        parent_id: message_tags_mt.id
      },
      %{
        label: "New Contact",
        shortcode: "newcontact",
        description: "Marking message as came from a new contact",
        parent_id: message_tags_mt.id
      },
      %{
        label: "Not replied",
        shortcode: "notreplied",
        description: "Marking message as not replied",
        parent_id: message_tags_mt.id
      },
      %{
        label: "Spam",
        shortcode: "spam",
        description: "Marking message as irrelevant or unsolicited message",
        parent_id: message_tags_mt.id
      },
      %{
        label: "Unread",
        shortcode: "unread",
        description: "Marking message as not read",
        parent_id: message_tags_mt.id
      },

      # Status of outbound Message
      %{
        label: "Not Responded",
        shortcode: "notresponded",
        description: "Marking message as not responded",
        parent_id: message_tags_mt.id
      },

      # Languages
      %{
        label: "Language",
        shortcode: "language",
        description: "Marking message as a name of a language",
        parent_id: message_tags_mt.id,
        keywords: ["hindi", "english", "हिंदी", "अंग्रेज़ी"]
      },

      # Optout
      %{
        label: "Optout",
        shortcode: "optout",
        description: "Marking message as a sign of opting out",
        parent_id: message_tags_mt.id,
        keywords: ["stop", "unsubscribe", "halt", "सदस्यता समाप्त"]
      },

      # Help
      %{
        label: "Help",
        shortcode: "help",
        description: "Marking message as a sign of requiring assistance",
        parent_id: message_tags_mt.id,
        keywords: ["help", "मदद"]
      },

      # Tags with Value
      %{
        label: "Numeric",
        shortcode: "numeric",
        description: "Marking message as a numeric type",
        parent_id: message_tags_mt.id,
        is_value: true
      },

      # Intent of message
      %{
        label: "Yes",
        shortcode: "yes",
        description: "Marking message as an affirmative response",
        parent_id: message_tags_mt.id,
        keywords: ["yes", "yeah", "okay", "ok"]
      },
      %{
        label: "No",
        shortcode: "no",
        description: "Marking message as a negative response",
        parent_id: message_tags_mt.id,
        keywords: ["no", "nope", "nay"]
      },

      # Type of Contact
      %{
        label: "Child",
        shortcode: "child",
        description: "Marking message as a child of a parent",
        parent_id: message_tags_ct.id
      },
      %{
        label: "Parent",
        shortcode: "parent",
        description: "Marking message as a parent of a child",
        parent_id: message_tags_ct.id
      },
      %{
        label: "Participant",
        shortcode: "participant",
        description: "Marking message as a participant",
        parent_id: message_tags_ct.id
      },
      %{
        label: "Staff",
        shortcode: "staff",
        description: "Marking message sent from a member of staff",
        parent_id: message_tags_ct.id
      }
    ]

    tags =
      Enum.map(
        tags,
        fn tag ->
          tag
          |> Map.put(:organization_id, organization.id)
          |> Map.put(:language_id, en_us.id)
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

  def contacts(organization, languages) do
    {_hi, en_us} = languages

    admin =
      Repo.insert!(%Contact{
        phone: @admin_phone,
        name: "Glific Admin",
        organization_id: organization.id,
        language_id: en_us.id,
        last_message_at: @now
      })

    Repo.update!(change(organization, contact_id: admin.id))
  end

  def organization(provider, languages) do
    {_hi, en_us} = languages

    out_of_office_default_data = %{
      enabled: false,
      enabled_days: [
        %{enabled: false, id: 1},
        %{enabled: false, id: 2},
        %{enabled: false, id: 3},
        %{enabled: false, id: 4},
        %{enabled: false, id: 5},
        %{enabled: false, id: 6},
        %{enabled: false, id: 7}
      ]
    }

    Repo.insert!(%Organization{
      name: "Glific",
      shortcode: "Glific",
      email: "ADMIN@REPLACE_ME.NOW",
      provider_id: provider.id,
      provider_key: "ADD_PROVIDER_API_KEY",
      provider_phone: @admin_phone,
      default_language_id: en_us.id,
      out_of_office: out_of_office_default_data
    })
  end

  def users(admin, organization) do
    Users.create_user(%{
      name: "Glific Admin",
      phone: @admin_phone,
      password: @password,
      confirm_password: @password,
      roles: ["admin"],
      contact_id: admin.id,
      organization_id: organization.id
    })
  end

  def hsm_templates(organization, languages) do
    {_hi, en_us} = languages

    Repo.insert!(%SessionTemplate{
      label: "Missed Message Apology",
      type: :text,
      shortcode: "missed_message",
      is_hsm: true,
      number_parameters: 0,
      language_id: en_us.id,
      organization_id: organization.id,
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
      organization_id: organization.id,
      body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
      uuid: "e55f2c10-541c-470b-a5ff-9249ae82bc95"
    })

    Repo.insert!(%SessionTemplate{
      label: "User Registration",
      body: """
      Please click on the link to register with the phone number @contact.phone
      @global.registration.url
      """,
      type: :text,
      shortcode: "user-registration",
      is_reserved: true,
      language_id: en_us.id,
      organization_id: organization.id,
      uuid: "fbf8d5a6-91ab-47ab-9691-35ef35443ad8"
    })
  end

  def saved_searches(organization) do
    labels =
      Repo.label_id_map(
        Tag,
        ["Not replied", "Not Responded", "Optout", "Unread"],
        organization.id,
        :label
      )

    data = [
      {"All conversations", "All"},
      {"All unread conversations", "Unread"},
      {"Conversations read but not replied", "Not replied"},
      {"Conversations where the contact has opted out", "Optout"},
      {"Conversations read but not responded", "Not Responded"}
    ]

    Enum.each(data, &saved_search(&1, organization, labels))
  end

  defp saved_search({label, shortcode}, organization, _labels) when shortcode == "All",
    do:
      Repo.insert!(%SavedSearch{
        label: label,
        shortcode: shortcode,
        args: %{
          filter: %{term: ""},
          contactOpts: %{limit: 20, offset: 0},
          messageOpts: %{limit: 10, offset: 0}
        },
        is_reserved: true,
        organization_id: organization.id
      })

  defp saved_search({label, shortcode}, organization, labels),
    do:
      Repo.insert!(%SavedSearch{
        label: label,
        shortcode: shortcode,
        args: %{
          filter: %{includeTags: [to_string(labels[shortcode])], term: ""},
          contactOpts: %{limit: 20, offset: 0},
          messageOpts: %{limit: 10, offset: 0}
        },
        is_reserved: true,
        organization_id: organization.id
      })

  def flows(organization) do
    data = [
      {"Help Workflow", "help", ["help", "मदद"], "3fa22108-f464-41e5-81d9-d8a298854429", true,
       "help.json"},
      {"Language Workflow", "language", ["language", "भाषा"],
       "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf", true, "language.json"},
      {"Preferences Workflow", "preference", ["preference"],
       "63397051-789d-418d-9388-2ef7eb1268bb", false, "preference.json"},
      {"New Contact Workflow", "newcontact", ["newcontact"],
       "6fe8fda9-2df6-4694-9fd6-45b9e724f545", false, "new_contact.json"},
      {"Registration Workflow", "registration", ["registration"],
       "f4f38e00-3a50-4892-99ce-a281fe24d040", false, "registration.json"},
      {"Out of Office Workflow", "outofoffice", ["outofoffice"],
       "af8a0aaa-dd10-4eee-b3b8-e59530e2f5f7", false, "out_of_office.json"},
      {"SoL Activity", "solactivity", ["solactivity"], "b050c652-65b5-4ccf-b62b-1e8b3f328676",
       false, "sol_activity.json"},
      {"sol_feedback", "solfeedback", ["solfeedback"], "6c21af89-d7de-49ac-9848-c9febbf737a5",
       false, "sol_feedback.json"}
    ]

    Enum.map(data, &flow(&1, organization))
  end

  defp flow({name, shortcode, keywords, uuid, ignore_keywords, file}, organization) do
    f =
      Repo.insert!(%Flow{
        name: name,
        shortcode: shortcode,
        keywords: keywords,
        ignore_keywords: ignore_keywords,
        version_number: "13.1.0",
        uuid: uuid,
        organization_id: organization.id
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
      flow_id: f.id,
      status: "done"
    })
  end

  def opted_in_contacts(organization) do
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
          provider_status: check_provider_status(last_message_at),
          organization_id: organization.id,
          language_id: organization.default_language_id
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

  def contacts_field(organization) do
    data = [
      {"Name", "name", :text, :contact},
      {"Age Group", "age_group", :text, :contact},
      {"Gender", "gender", :text, :contact},
      {"Date of Birth", "dob", :text, :contact},
      {"Settings", "settings", :text, :contact}
    ]

    Enum.map(data, &contacts_field(&1, organization))
  end

  defp contacts_field({name, shortcode, value_type, scope}, organization) do
    Repo.insert!(%ContactsField{
      name: name,
      shortcode: shortcode,
      value_type: value_type,
      scope: scope,
      organization_id: organization.id
    })
  end
end
