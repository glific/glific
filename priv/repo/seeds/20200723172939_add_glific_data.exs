defmodule Glific.Repo.Seeds.AddGlificData do
  use Glific.Seeds.Seed
  import Ecto.Changeset, only: [change: 2]

  envs([:dev, :test, :prod])

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactsField,
    Flows.Flow,
    Flows.FlowLabel,
    Flows.FlowRevision,
    Jobs.BigqueryJob,
    Partners,
    Partners.Organization,
    Partners.Provider,
    Repo,
    Searches.SavedSearch,
    Settings.Language,
    Tags.Tag,
    Templates.SessionTemplate,
    Users
  }

  @password "secret1234"
  @admin_phone "917834811114"

  defp admin_phone(1 = _organization_id), do: @admin_phone

  defp admin_phone(organization_id),
    do: (String.to_integer(@admin_phone) + organization_id) |> Integer.to_string()

  def up(_repo) do
    # check if this is the first organization that we are adding
    # to the DB
    count_organizations = Partners.count_organizations()

    en_us = languages(count_organizations)

    provider = providers(count_organizations)

    organization = organization(count_organizations, provider, en_us)

    # calling it gtags, since tags is a macro in philcolumns
    gtags(organization, en_us)

    admin = contacts(organization, en_us)

    users(admin, organization)

    hsm_templates(organization, en_us)

    saved_searches(organization)

    flow_labels(organization)

    flows(organization)

    contacts_field(organization)

    bigquery_jobs(organization)
  end

  def down(_repo) do
    # this is the first migration, so all tables are empty
    # hence we can get away with truncating in reverse order
    # DO NOT FOLLOW this pattern for any other migrations
    truncates = [
      "TRUNCATE flow_revisions CASCADE;",
      "TRUNCATE flows CASCADE;",
      "TRUNCATE saved_searches CASCADE;",
      "TRUNCATE session_templates CASCADE;",
      "TRUNCATE users CASCADE;",
      "TRUNCATE contacts CASCADE;",
      "TRUNCATE tags CASCADE;",
      "TRUNCATE contacts_fields CASCADE;",
      "TRUNCATE organizations CASCADE;",
      "TRUNCATE providers CASCADE;",
      "TRUNCATE languages CASCADE;"
    ]

    Enum.each(truncates, fn t -> Repo.query(t) end)
  end

  def languages(0 = _count_organizations) do
    en_us =
      Repo.insert!(%Language{
        label: "English (United States)",
        label_locale: "English",
        locale: "en_US"
      })

    languages = [
      {"Hindi", "हिंदी", "hi"},
      {"Tamil", "தமிழ்", "ta"},
      {"Kannada", "ಕನ್ನಡ", "kn"},
      {"Malayalam", "മലയാളം", "ml"},
      {"Telugu", "తెలుగు", "te"},
      {"Odia", "ଓଡ଼ିଆ", "or"},
      {"Assamese", "অসমীয়া", "as"},
      {"Gujarati", "ગુજરાતી", "gu"},
      {"Bengali", "বাংলা", "bn"},
      {"Punjabi", "ਪੰਜਾਬੀ", "pa"},
      {"Marathi", "मराठी", "mr"}
    ]

    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    languages =
      Enum.map(
        languages,
        fn {label, label_locale, locale} ->
          %{
            label: label,
            label_locale: label_locale,
            locale: locale,
            inserted_at: utc_now,
            updated_at: utc_now
          }
        end
      )

    # seed languages
    Repo.insert_all(Language, languages)

    en_us
  end

  def languages(_count_organizations) do
    {:ok, en_us} = Repo.fetch_by(Language, %{label: "English (United States)"})
    en_us
  end

  def gtags(organization, en_us) do
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

    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    tags =
      Enum.map(
        tags,
        fn tag ->
          tag
          |> Map.put(:organization_id, organization.id)
          |> Map.put(:language_id, en_us.id)
          |> Map.put(:is_reserved, true)
          |> Map.put(:inserted_at, utc_now)
          |> Map.put(:updated_at, utc_now)
        end
      )

    # seed multiple tags
    Repo.insert_all(Tag, tags)
  end

  def providers(0 = _count_organizations) do
    default =
      Repo.insert!(%Provider{
        name: "Gupshup",
        shortcode: "gupshup",
        group: "bsp",
        is_required: true,
        keys: %{
          url: %{
            type: :string,
            label: "BSP Home Page",
            default: "https://gupshup.io/",
            view_only: true
          },
          api_end_point: %{
            type: :string,
            label: "API End Point",
            default: "https://api.gupshup.io/sm/api/v1",
            view_only: false
          },
          handler: %{
            type: :string,
            label: "Inbound Message Handler",
            default: "Glific.Providers.Gupshup.Message",
            view_only: true
          },
          worker: %{
            type: :string,
            label: "Outbound Message Worker",
            default: "Glific.Providers.Gupshup.Worker",
            view_only: true
          }
        },
        secrets: %{
          api_key: %{
            type: :string,
            label: "API Key",
            default: nil,
            view_only: false
          },
          app_name: %{
            type: :string,
            label: "App Name",
            default: nil,
            view_only: false
          }
        }
      })

    # add glifproxy as a provider also
    Repo.insert!(%Provider{
      name: "Glifproxy",
      shortcode: "glifproxy",
      group: "bsp",
      is_required: true,
      keys: %{
        url: %{
          type: :string,
          label: "BSP Home Page",
          default: "https://glific.io/",
          view_only: true
        },
        api_end_point: %{
          type: :string,
          label: "API End Point",
          default: "https://glific.test:4000/",
          view_only: false
        },
        handler: %{
          type: :string,
          label: "Inbound Message Handler",
          default: "Glific.Providers.Gupshup.Message",
          view_only: true
        },
        worker: %{
          type: :string,
          label: "Outbound Message Worker",
          default: "Glific.Providers.Glifproxy.Worker",
          view_only: true
        }
      },
      secrets: %{}
    })

    default
  end

  def providers(_count_organizations) do
    {:ok, default} = Repo.fetch_by(Provider, %{name: "Gupshup"})
    default
  end

  def contacts(organization, en_us) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    admin =
      Repo.insert!(%Contact{
        phone: admin_phone(organization.id),
        name: "Glific Admin",
        organization_id: organization.id,
        language_id: en_us.id,
        last_message_at: utc_now
      })

    Repo.update!(change(organization, contact_id: admin.id))
    admin
  end

  defp create_org(0 = _count_organizations, provider, en_us, out_of_office_default_data) do
    Repo.insert!(%Organization{
      name: "Glific",
      shortcode: "glific",
      email: "ADMIN@REPLACE_ME.NOW",
      bsp_id: provider.id,
      active_language_ids: [en_us.id],
      default_language_id: en_us.id,
      out_of_office: out_of_office_default_data
    })
  end

  defp create_org(count_organizations, provider, en_us, out_of_office_default_data) do
    org_uniq_id = Integer.to_string(count_organizations + 1)

    Repo.insert!(%Organization{
      name: "New Seeded Organization " <> org_uniq_id,
      shortcode: "shortcode " <> org_uniq_id,
      email: "ADMIN_#{org_uniq_id}@REPLACE_ME.NOW",
      bsp_id: provider.id,
      active_language_ids: [en_us.id],
      default_language_id: en_us.id,
      out_of_office: out_of_office_default_data
    })
  end

  def organization(count_organization, provider, en_us) do
    out_of_office_default_data = %{
      enabled: true,
      start_time: elem(Time.new(9, 0, 0), 1),
      end_time: elem(Time.new(20, 0, 0), 1),
      enabled_days: [
        %{enabled: true, id: 1},
        %{enabled: true, id: 2},
        %{enabled: true, id: 3},
        %{enabled: true, id: 4},
        %{enabled: true, id: 5},
        %{enabled: false, id: 6},
        %{enabled: false, id: 7}
      ]
    }

    create_org(count_organization, provider, en_us, out_of_office_default_data)
  end

  def users(admin, organization) do
    Users.create_user(%{
      name: "Glific Admin",
      phone: admin_phone(organization.id),
      password: @password,
      confirm_password: @password,
      roles: ["admin"],
      contact_id: admin.id,
      organization_id: organization.id
    })
  end

  defp generate_uuid(organization, default) do
    # we have static uuids for the first organization since we might have our test cases
    # hardcoded with these uuids
    if organization.id == 1,
      do: default,
      else: Ecto.UUID.generate()
  end

  def hsm_templates(organization, en_us) do
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
      uuid: generate_uuid(organization, "9381b1b9-1b9b-45a6-81f4-f91306959619")
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
      uuid: generate_uuid(organization, "e55f2c10-541c-470b-a5ff-9249ae82bc95")
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
      uuid: generate_uuid(organization, "fbf8d5a6-91ab-47ab-9691-35ef35443ad8")
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

  # Pre defined collections
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

  defp flow_labels(organization) do
    flow_labels = [
      %{name: "Poetry"},
      %{name: "Visual Arts"},
      %{name: "Theatre"},
      %{name: "Understood"},
      %{name: "Not Understood"},
      %{name: "Interesting"},
      %{name: "Boring"},
      %{name: "Age Group less than 10"},
      %{name: "Age Group 11 to 14"},
      %{name: "Age Group 15 to 18"},
      %{name: "Age Group 19 or above"},
      %{name: "Hindi"},
      %{name: "English"},
      %{name: "Help"},
      %{name: "New Activity"}
    ]

    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    flow_labels =
      Enum.map(
        flow_labels,
        fn tag ->
          tag
          |> Map.put(:organization_id, organization.id)
          |> Map.put(:uuid, Ecto.UUID.generate())
          |> Map.put(:inserted_at, utc_now)
          |> Map.put(:updated_at, utc_now)
        end
      )

    # seed multiple flow labels
    Repo.insert_all(FlowLabel, flow_labels)
  end

  def flows(organization) do
    uuid_map = %{
      help: generate_uuid(organization, "3fa22108-f464-41e5-81d9-d8a298854429"),
      language: generate_uuid(organization, "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf"),
      preference: generate_uuid(organization, "63397051-789d-418d-9388-2ef7eb1268bb"),
      newcontact: generate_uuid(organization, "6fe8fda9-2df6-4694-9fd6-45b9e724f545"),
      registration: generate_uuid(organization, "f4f38e00-3a50-4892-99ce-a281fe24d040"),
      outofoffice: generate_uuid(organization, "af8a0aaa-dd10-4eee-b3b8-e59530e2f5f7"),
      activity: generate_uuid(organization, "b050c652-65b5-4ccf-b62b-1e8b3f328676"),
      feedback: generate_uuid(organization, "6c21af89-d7de-49ac-9848-c9febbf737a5"),
      optout: generate_uuid(organization, "bc1622f8-64f8-4b3d-b767-bb6bbfb65104")
    }

    flow_labels_id_map =
      FlowLabel.get_all_flowlabel(organization.id)
      |> Enum.reduce(%{}, fn flow_label, acc ->
        acc |> Map.merge(%{flow_label.name => flow_label.uuid})
      end)

    data = [
      {"Help Workflow", ["help", "मदद"], uuid_map.help, true, "help.json"},
      {"Language Workflow", ["language", "भाषा"], uuid_map.language, true, "language.json"},
      {"Preference Workflow", ["preference"], uuid_map.preference, false, "preference.json"},
      {"New Contact Workflow", ["newcontact"], uuid_map.newcontact, false, "new_contact.json"},
      {"Registration Workflow", ["registration"], uuid_map.registration, false,
       "registration.json"},
      {"Out of Office Workflow", ["outofoffice"], uuid_map.outofoffice, false,
       "out_of_office.json"},
      {"Activity", ["activity"], uuid_map.activity, false, "activity.json"},
      {"Feedback", ["feedback"], uuid_map.feedback, false, "feedback.json"},
      {"Optout Workflow", ["optout"], uuid_map.optout, false, "optout.json"}
    ]

    Enum.map(data, &flow(&1, organization, uuid_map, flow_labels_id_map))
  end

  defp replace_uuids(json, uuid_map),
    do:
      Enum.reduce(
        uuid_map,
        json,
        fn {key, uuid}, acc ->
          String.replace(
            acc,
            key |> Atom.to_string() |> String.upcase() |> Kernel.<>("_UUID"),
            uuid
          )
        end
      )

  defp replace_label_uuids(json, flow_labels_id_map),
    do:
      Enum.reduce(
        flow_labels_id_map,
        json,
        fn {key, id}, acc ->
          String.replace(
            acc,
            key |> Kernel.<>(":ID"),
            "#{id}"
          )
        end
      )

  defp flow({name, keywords, uuid, ignore_keywords, file}, organization, uuid_map, id_map) do
    f =
      Repo.insert!(%Flow{
        name: name,
        keywords: keywords,
        ignore_keywords: ignore_keywords,
        version_number: "13.1.0",
        uuid: uuid,
        organization_id: organization.id
      })

    definition =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/" <> file))
      |> replace_uuids(uuid_map)
      |> replace_label_uuids(id_map)
      |> Jason.decode!()
      |> Map.merge(%{
        "name" => f.name,
        "uuid" => f.uuid
      })

    Repo.insert(%FlowRevision{
      definition: definition,
      flow_id: f.id,
      status: "done",
      version: 1,
    })
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

  defp bigquery_jobs(organization) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%BigqueryJob{
      table: "messages",
      table_id: 0,
      organization_id: organization.id,
      inserted_at: utc_now,
      updated_at: utc_now
    })

    Repo.insert!(%BigqueryJob{
      table: "contacts",
      table_id: 0,
      organization_id: organization.id,
      inserted_at: utc_now,
      updated_at: utc_now
    })
  end
end
