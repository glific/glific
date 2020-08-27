defmodule Glific.Repo.Seeds.AddGlificData do
  use Glific.Seeds.Seed
  import Ecto.Changeset, only: [change: 2]

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

    ta =
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
        is_reserved: true,
        language_id: en_us.id,
        organization_id: organization.id
      })

    message_tags_ct =
      Repo.insert!(%Tag{
        label: "Contacts",
        shortcode: "contacts",
        is_reserved: true,
        language_id: en_us.id,
        organization_id: organization.id
      })

    tags = [
      # Intent of message
      %{
        label: "Good Bye",
        shortcode: "goodbye",
        parent_id: message_tags_mt.id,
        keywords: ["bye", "byebye", "goodbye", "goodnight", "goodnite"]
      },
      %{
        label: "Greeting",
        shortcode: "greeting",
        parent_id: message_tags_mt.id,
        keywords: ["hello", "goodmorning", "hi", "hey"]
      },
      %{
        label: "Thank You",
        shortcode: "thankyou",
        parent_id: message_tags_mt.id,
        keywords: ["thanks", "thankyou", "awesome", "great"]
      },

      # Status of Message
      %{
        label: "Important",
        shortcode: "important",
        parent_id: message_tags_mt.id
      },
      %{
        label: "New Contact",
        shortcode: "newcontact",
        parent_id: message_tags_mt.id
      },
      %{
        label: "Not replied",
        shortcode: "notreplied",
        parent_id: message_tags_mt.id
      },
      %{label: "Spam", shortcode: "spam", parent_id: message_tags_mt.id},
      %{
        label: "Unread",
        shortcode: "unread",
        parent_id: message_tags_mt.id
      },

      # Status of outbound Message
      %{
        label: "Not Responded",
        shortcode: "notresponded",
        parent_id: message_tags_mt.id
      },

      # Languages
      %{
        label: "Language",
        shortcode: "language",
        parent_id: message_tags_mt.id,
        keywords: ["hindi", "english", "हिंदी", "अंग्रेज़ी"]
      },

      # Optout
      %{
        label: "Optout",
        shortcode: "optout",
        parent_id: message_tags_mt.id,
        keywords: ["stop", "unsubscribe", "halt", "सदस्यता समाप्त"]
      },

      # Help
      %{
        label: "Help",
        shortcode: "help",
        parent_id: message_tags_mt.id,
        keywords: ["help", "मदद"]
      },

      # Tags with Value
      %{
        label: "Numeric",
        shortcode: "numeric",
        parent_id: message_tags_mt.id,
        is_value: true
      },

      # Intent of message
      %{
        label: "Yes",
        shortcode: "yes",
        parent_id: message_tags_mt.id,
        keywords: ["yes", "yeah", "okay", "ok"]
      },
      %{
        label: "No",
        shortcode: "no",
        parent_id: message_tags_mt.id,
        keywords: ["no", "nope", "nay"]
      },

      # Type of Contact
      %{label: "Child", shortcode: "child", parent_id: message_tags_ct.id},
      %{
        label: "Parent",
        shortcode: "parent",
        parent_id: message_tags_ct.id
      },
      %{
        label: "Participant",
        shortcode: "participant",
        parent_id: message_tags_ct.id
      },
      %{label: "Staff", shortcode: "staff", parent_id: message_tags_ct.id}
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
      display_name: "Glific",
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
    {hi, en_us} = languages

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
      label: "User Regitstration",
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
    labels = Repo.label_id_map(Tag, ["Not replied", "Not Responded", "Optout", "Unread"])

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

    Enum.map(data, &flow(&1, organization))
  end

  defp flow({name, shortcode, keywords, uuid, file}, organization) do
    f =
      Repo.insert!(%Flow{
        name: name,
        shortcode: shortcode,
        keywords: keywords,
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
          organization_id: organization.id
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
