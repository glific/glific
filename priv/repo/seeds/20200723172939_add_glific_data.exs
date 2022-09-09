defmodule Glific.Repo.Seeds.AddGlificData do
  use Glific.Seeds.Seed
  import Ecto.Changeset, only: [change: 2]

  envs([:dev, :test, :prod])

  alias Glific.{
    AccessControl,
    Contacts.Contact,
    Contacts.ContactsField,
    Flows.Flow,
    Flows.FlowLabel,
    BigQuery.BigQueryJob,
    Partners,
    Partners.Organization,
    Partners.Provider,
    Partners.Saas,
    Profiles.Profile,
    Repo,
    Searches.SavedSearch,
    Seeds.SeedsDev,
    Seeds.SeedsFlows,
    Seeds.SeedsMigration,
    Settings.Language,
    Tags.Tag,
    Users
  }

  @password "secret1234"
  @admin_phone "917834811114"

  defp admin_phone(1 = _organization_id), do: @admin_phone

  defp admin_phone(organization_id),
    do: (String.to_integer(@admin_phone) + organization_id) |> Integer.to_string()

  def up(_repo, opts) do
    # check if this is the first organization that we are adding
    # to the DB

    tenant_id = Keyword.get(opts, :tenant_id, nil)

    count_organizations = Partners.count_organizations()

    [en, hi] = languages(count_organizations)

    provider = providers(count_organizations)

    organization =
      if is_nil(tenant_id),
        do: organization(count_organizations, provider, [en, hi]),
        else: Partners.get_organization!(tenant_id)

    ## Added organization id in the query
    Glific.Repo.put_organization_id(organization.id)

    # Add the SaaS row
    saas(count_organizations, organization)

    # calling it gtags, since tags is a macro in philcolumns
    gtags(organization, en)

    admin =
      if is_nil(tenant_id),
        do: contacts(organization, en),
        else: Repo.get!(Contact, organization.contact_id)

    if not is_nil(tenant_id) do
      set_organization_language(organization, [en, hi])
      set_out_of_office(organization)
      set_bsp_id(organization, provider)
    end

    profiles(organization, admin)

    if is_nil(tenant_id), do: users(admin, organization)

    SeedsMigration.migrate_data(:simulator, organization)

    SeedsMigration.migrate_data(:collection, organization)

    SeedsMigration.migrate_data(:localized_language, organization)

    SeedsMigration.migrate_data(:user_default_language, organization)

    saved_searches(organization)

    flow_labels(organization)

    flows(organization)

    roles(organization)

    user_roles(organization)

    contacts_field(organization)

    bigquery_jobs(organization)

    set_newcontact_flow_id(organization)
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
      "TRUNCATE languages CASCADE;",
      "TRUNCATE profiles, CASCADE;"
    ]

    Enum.each(truncates, fn t -> Repo.query(t) end)
  end

  def utc_now(), do: DateTime.utc_now() |> DateTime.truncate(:second)

  def languages(0 = _count_organizations) do
    en =
      Repo.insert!(%Language{
        label: "English",
        label_locale: "English",
        locale: "en"
      })

    hi =
      Repo.insert!(%Language{
        label: "Hindi",
        label_locale: "हिंदी",
        locale: "hi"
      })

    languages = [
      {"Tamil", "தமிழ்", "ta"},
      {"Kannada", "ಕನ್ನಡ", "kn"},
      {"Malayalam", "മലയാളം", "ml"},
      {"Telugu", "తెలుగు", "te"},
      {"Odia", "ଓଡ଼ିଆ", "or"},
      {"Assamese", "অসমীয়া", "as"},
      {"Gujarati", "ગુજરાતી", "gu"},
      {"Bengali", "বাংলা", "bn"},
      {"Punjabi", "ਪੰਜਾਬੀ", "pa"},
      {"Marathi", "मराठी", "mr"},
      {"Urdu", "اردو", "ur"},
      {"Spanish", "Español", "es"},
      {"Sign Language", "ISL", "isl"}
    ]

    languages =
      Enum.map(
        languages,
        fn {label, label_locale, locale} ->
          %{
            label: label,
            label_locale: label_locale,
            locale: locale,
            inserted_at: utc_now(),
            updated_at: utc_now()
          }
        end
      )

    # seed languages
    Repo.insert_all(Language, languages)

    [en, hi]
  end

  def languages(_count_organizations) do
    {:ok, en} = Repo.fetch_by(Language, %{label: "English"})
    {:ok, hi} = Repo.fetch_by(Language, %{label: "Hindi"})
    [en, hi]
  end

  defp saas(0, organization) do
    Repo.insert!(%Saas{
      name: "Tides",
      organization_id: organization.id,
      email: "glific@glific.com",
      phone: "91111222333",
      stripe_ids: Enum.into(get_stripe_ids(), %{}),
      tax_rates: %{
        gst: "txr_1IjH4wEMShkCsLFnSIELvS4n"
      },
      isv_credentials: %{email: "test_email", user: "test user"}
    })
  end

  defp saas(_count, _organization), do: nil

  defp get_stripe_ids(),
    do: default_ids()

  defp default_ids(),
    do: [
      product: "prod_JG5ns5s9yPRiOq",
      setup: "price_1IdZeIEMShkCsLFn5OdWiuC4",
      monthly: "price_1IdZbfEMShkCsLFn8TF0NLPO",
      users: "price_1IdZehEMShkCsLFnyYhuDu6p",
      messages: "price_1IdZdTEMShkCsLFnPAf9zzym",
      consulting_hours: "price_1IdZe5EMShkCsLFncGatvTCk",
      inactive: "price_1ImvA9EMShkCsLFnTtiXOslM"
    ]

  def gtags(organization, en) do
    # seed tags
    message_tags_mt =
      Repo.insert!(%Tag{
        label: "Messages",
        shortcode: "messages",
        description: "A default message tag",
        is_reserved: true,
        language_id: en.id,
        organization_id: organization.id
      })

    message_tags_ct =
      Repo.insert!(%Tag{
        label: "Contacts",
        shortcode: "contacts",
        description: "A contact tag for users that are marked as contacts",
        is_reserved: true,
        language_id: en.id,
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
        label: "Spam",
        shortcode: "spam",
        description: "Marking message as irrelevant or unsolicited message",
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
          |> Map.put(:language_id, en.id)
          |> Map.put(:is_reserved, true)
          |> Map.put(:inserted_at, utc_now())
          |> Map.put(:updated_at, utc_now())
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
          },
          app_id: %{
            type: :string,
            label: "App ID",
            default: "App ID",
            view_only: true
          }
        }
      })

    default
  end

  def providers(_count_organizations) do
    {:ok, default} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})
    default
  end

  def contacts(organization, en) do
    admin =
      Repo.insert!(%Contact{
        phone: admin_phone(organization.id),
        name: "NGO Main Account",
        organization_id: organization.id,
        language_id: en.id,
        last_message_at: utc_now(),
        last_communication_at: utc_now()
      })

    Repo.update!(change(organization, contact_id: admin.id))
    admin
  end

  def profiles(organization, contact) do
    Repo.insert!(%Profile{
      name: "user",
      type: "profile",
      organization_id: organization.id,
      contact_id: contact.id,
      language_id: contact.language_id
    })
  end

  defp create_org(0 = _count_organizations, provider, [en, hi], out_of_office_default_data) do
    Repo.insert!(%Organization{
      name: "Glific",
      shortcode: "glific",
      email: "ADMIN@REPLACE_ME.NOW",
      bsp_id: provider.id,
      active_language_ids: [en.id, hi.id],
      default_language_id: en.id,
      out_of_office: out_of_office_default_data,
      signature_phrase: "Please change me, NOW!",
      is_active: true,
      is_approved: true,
      status: :active
    })
  end

  defp create_org(count_organizations, provider, [en, hi], out_of_office_default_data) do
    org_uniq_id = Integer.to_string(count_organizations + 1)

    Repo.insert!(%Organization{
      name: "New Seeded Organization " <> org_uniq_id,
      shortcode: "shortcode " <> org_uniq_id,
      email: "ADMIN_#{org_uniq_id}@REPLACE_ME.NOW",
      bsp_id: provider.id,
      active_language_ids: [en.id, hi.id],
      default_language_id: en.id,
      out_of_office: out_of_office_default_data,
      signature_phrase: "Please change me, NOW!",
      is_active: true,
      is_approved: true,
      status: :active
    })
  end

  def organization(count_organization, provider, [en, hi]) do
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

    create_org(count_organization, provider, [en, hi], out_of_office_default_data)
  end

  def users(admin, organization) do
    Users.create_user(%{
      name: "NGO Main Account",
      phone: admin_phone(organization.id),
      password: @password,
      confirm_password: @password,
      roles: ["admin"],
      contact_id: admin.id,
      organization_id: organization.id
    })
  end

  def saved_searches(organization) do
    data = [
      {"All conversations", "All"},
      {"All unread conversations", "Unread"},
      {"Conversations read but not replied", "Not replied"},
      {"Conversations read but not responded", "Not Responded"},
      {"Conversations where the contact has opted in", "Optin"},
      {"Conversations where the contact has opted out", "Optout"}
    ]

    Enum.each(data, &saved_search(&1, organization))
  end

  # Pre defined collections
  defp saved_search({label, shortcode}, organization) when shortcode == "All",
    do:
      Repo.insert!(%SavedSearch{
        label: label,
        shortcode: shortcode,
        args: %{
          filter: %{},
          contactOpts: %{limit: 25},
          messageOpts: %{limit: 20}
        },
        is_reserved: true,
        organization_id: organization.id
      })

  defp saved_search({label, shortcode}, organization),
    do:
      Repo.insert!(%SavedSearch{
        label: label,
        shortcode: shortcode,
        args: %{
          filter: %{status: shortcode, term: ""},
          contactOpts: %{limit: 25, offset: 0},
          messageOpts: %{limit: 20, offset: 0}
        },
        is_reserved: true,
        organization_id: organization.id
      })

  defp flow_labels(organization) do
    flow_labels = [
      %{name: "Age Group less than 10"},
      %{name: "Age Group 11 to 14"},
      %{name: "Age Group 15 to 18"},
      %{name: "Age Group 19 or above"},
      %{name: "Hindi"},
      %{name: "English"}
    ]

    flow_labels =
      Enum.map(
        flow_labels,
        fn tag ->
          tag
          |> Map.put(:organization_id, organization.id)
          |> Map.put(:uuid, Ecto.UUID.generate())
          |> Map.put(:inserted_at, utc_now())
          |> Map.put(:updated_at, utc_now())
        end
      )

    # seed multiple flow labels
    Repo.insert_all(FlowLabel, flow_labels)
  end

  def flows(organization),
    do: SeedsFlows.seed([organization])

  def roles(organization),
    do: SeedsDev.seed_roles(organization)

  def user_roles(organization) do
    [u1, u2] = Users.list_users(%{filter: %{organization_id: organization.id}})

    {:ok, r1} = Repo.fetch_by(AccessControl.Role, %{label: "Admin"})

    Repo.insert!(%AccessControl.UserRole{
      user_id: u1.id,
      role_id: r1.id,
      organization_id: organization.id
    })

    Repo.insert!(%AccessControl.UserRole{
      user_id: u2.id,
      role_id: r1.id,
      organization_id: organization.id
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

    Repo.insert!(%BigQueryJob{
      table: "messages",
      table_id: 0,
      organization_id: organization.id,
      inserted_at: utc_now,
      updated_at: utc_now
    })

    Repo.insert!(%BigQueryJob{
      table: "contacts",
      table_id: 0,
      organization_id: organization.id,
      inserted_at: utc_now,
      updated_at: utc_now
    })

    Repo.insert!(%BigQueryJob{
      table: "flows",
      table_id: 0,
      organization_id: organization.id,
      inserted_at: utc_now,
      updated_at: utc_now
    })

    Repo.insert!(%BigQueryJob{
      table: "flow_results",
      table_id: 0,
      organization_id: organization.id,
      inserted_at: utc_now,
      updated_at: utc_now
    })

    Repo.insert!(%BigQueryJob{
      table: "stats",
      table_id: 0,
      organization_id: organization.id,
      inserted_at: utc_now,
      updated_at: utc_now
    })
  end

  @spec set_newcontact_flow_id(Organization.t()) :: Organization.t()
  defp set_newcontact_flow_id(organization) do
    {:ok, flow} =
      Repo.fetch_by(Flow, %{
        name: "New Contact Workflow",
        organization_id: organization.id
      })

    organization
    |> Partners.update_organization(%{newcontact_flow_id: flow.id})
  end

  defp set_organization_language(organization, [en, hi]) do
    organization
    |> change(%{active_language_ids: [en.id, hi.id], default_language_id: en.id})
    |> Repo.update!()
  end

  defp set_out_of_office(organization) do
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

    organization
    |> change(%{out_of_office: out_of_office_default_data})
    |> Repo.update!()
  end

  defp set_bsp_id(organization, provider) do
    organization
    |> change(%{bsp_id: provider.id})
    |> Repo.update!()
  end
end
