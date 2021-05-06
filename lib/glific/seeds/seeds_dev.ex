if Code.ensure_loaded?(Faker) do
  defmodule Glific.Seeds.SeedsDev do
    @moduledoc """
    Script for populating the database. We can call this from tests and/or /priv/repo
    """
    alias Glific.{
      Contacts,
      Contacts.Contact,
      Flows.Flow,
      Flows.FlowLabel,
      Flows.FlowResult,
      Flows.FlowRevision,
      Groups,
      Groups.Group,
      Messages.Message,
      Messages.MessageMedia,
      Partners.Billing,
      Partners.Organization,
      Partners.Provider,
      Repo,
      Seeds.SeedsFlows,
      Settings,
      Settings.Language,
      Tags.Tag,
      Templates.SessionTemplate,
      Users
    }

    alias Faker.Lorem.Shakespeare

    @doc """
    Smaller functions to seed various tables. This allows the test functions to call specific seeder functions.
    In the next phase we will also add unseeder functions as we learn more of the test capabilities
    """
    @spec seed_tag(Organization.t() | nil) :: nil
    def seed_tag(organization \\ nil) do
      organization = get_organization(organization)

      [hi_in | _] = Settings.list_languages(%{filter: %{label: "hindi"}})
      [en | _] = Settings.list_languages(%{filter: %{label: "english"}})

      Repo.insert!(%Tag{
        label: "This is for testing",
        shortcode: "testing-only",
        description: "Marking message for testing purpose in English Language",
        language: en,
        organization: organization
      })

      Repo.insert!(%Tag{
        label: "यह परीक्षण के लिए है",
        shortcode: "testing-only",
        description: "Marking message for testing purpose in Hindi Language",
        language: hi_in,
        organization: organization
      })
    end

    @doc false
    @spec seed_contacts(Organization.t() | nil) :: {integer(), nil}
    def seed_contacts(organization \\ nil) do
      organization = get_organization(organization)

      utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

      [hi_in | _] = Settings.list_languages(%{filter: %{label: "hindi"}})
      [en | _] = Settings.list_languages(%{filter: %{label: "english"}})

      contacts = [
        %{
          phone: "917834811231",
          name: "Default receiver",
          language_id: hi_in.id,
          optin_time: utc_now,
          optin_status: true,
          optin_method: "BSP",
          bsp_status: :session_and_hsm
        },
        %{
          name: "Adelle Cavin",
          phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
          language_id: hi_in.id,
          bsp_status: :session_and_hsm,
          optin_time: utc_now,
          optin_status: true
        },
        %{
          name: "Margarita Quinteros",
          phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
          language_id: hi_in.id,
          bsp_status: :session_and_hsm,
          optin_time: utc_now,
          optin_status: true
        },
        %{
          name: "Chrissy Cron",
          phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
          language_id: en.id,
          bsp_status: :session_and_hsm,
          optin_time: utc_now,
          optin_status: true
        }
      ]

      utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

      contact_entries =
        for contact_entry <- contacts do
          %{
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now(),
            organization_id: organization.id,
            last_message_at: utc_now,
            last_communication_at: utc_now,
            optin_status: false,
            bsp_status: :session
          }
          |> Map.merge(contact_entry)
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
          shortcode: "shortcode",
          keys: %{},
          secrets: %{}
        })

      default_provider
    end

    @doc false
    @spec seed_organizations(non_neg_integer | nil) :: Organization.t() | nil
    def seed_organizations(_organization_id \\ nil) do
      Organization |> Ecto.Query.first() |> Repo.one(skip_organization_id: true)
    end

    @doc false
    @spec seed_messages(Organization.t() | nil) :: nil
    def seed_messages(organization \\ nil) do
      organization = get_organization(organization)

      {:ok, sender} =
        Repo.fetch_by(
          Contact,
          %{name: "NGO Main Account", organization_id: organization.id}
        )

      {:ok, receiver} =
        Repo.fetch_by(
          Contact,
          %{name: "Default receiver", organization_id: organization.id}
        )

      {:ok, receiver2} =
        Repo.fetch_by(
          Contact,
          %{name: "Adelle Cavin", organization_id: organization.id}
        )

      {:ok, receiver3} =
        Repo.fetch_by(
          Contact,
          %{name: "Margarita Quinteros", organization_id: organization.id}
        )

      {:ok, receiver4} =
        Repo.fetch_by(
          Contact,
          %{name: "Chrissy Cron", organization_id: organization.id}
        )

      Repo.insert!(%Message{
        body: "Default message body",
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: sender.id,
        receiver_id: receiver.id,
        contact_id: receiver.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: "ZZZ message body for order test",
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: sender.id,
        receiver_id: receiver.id,
        contact_id: receiver.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: Shakespeare.hamlet(),
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: sender.id,
        receiver_id: receiver.id,
        contact_id: receiver.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: Shakespeare.hamlet(),
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: sender.id,
        receiver_id: receiver.id,
        contact_id: receiver.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: "hindi",
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: receiver.id,
        receiver_id: sender.id,
        contact_id: receiver.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: "english",
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: receiver.id,
        receiver_id: sender.id,
        contact_id: receiver.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: "hola",
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: receiver.id,
        receiver_id: sender.id,
        contact_id: receiver.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: Shakespeare.hamlet(),
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: receiver2.id,
        receiver_id: sender.id,
        contact_id: receiver2.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: Shakespeare.hamlet(),
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: receiver3.id,
        receiver_id: sender.id,
        contact_id: receiver3.id,
        organization_id: organization.id
      })

      Repo.insert!(%Message{
        body: Shakespeare.hamlet(),
        flow: :inbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: receiver4.id,
        receiver_id: sender.id,
        contact_id: receiver4.id,
        organization_id: organization.id
      })
    end

    @doc false
    @spec seed_messages_media(Organization.t() | nil) :: nil
    def seed_messages_media(organization \\ nil) do
      organization = get_organization(organization)

      Repo.insert!(%MessageMedia{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        caption: "default caption",
        provider_media_id: Faker.String.base64(10),
        organization_id: organization.id
      })

      Repo.insert!(%MessageMedia{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        caption: Faker.String.base64(10),
        provider_media_id: Faker.String.base64(10),
        organization_id: organization.id
      })

      Repo.insert!(%MessageMedia{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        caption: Faker.String.base64(10),
        provider_media_id: Faker.String.base64(10),
        organization_id: organization.id
      })

      Repo.insert!(%MessageMedia{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        caption: Faker.String.base64(10),
        provider_media_id: Faker.String.base64(10),
        organization_id: organization.id
      })
    end

    defp create_contact_user(
           {organization, en, utc_now},
           {name, phone, roles}
         ) do
      password = "12345678"

      contact =
        Repo.insert!(%Contact{
          phone: phone,
          name: name,
          language_id: en.id,
          optin_time: utc_now,
          optin_status: true,
          optin_method: "BSP",
          last_message_at: utc_now,
          last_communication_at: utc_now,
          organization_id: organization.id
        })

      {:ok, user} =
        Users.create_user(%{
          name: name,
          phone: phone,
          password: password,
          confirm_password: password,
          roles: roles,
          contact_id: contact.id,
          last_login_at: utc_now,
          last_login_from: "127.0.0.1",
          organization_id: organization.id
        })

      {contact, user}
    end

    @doc false
    @spec seed_users(Organization.t() | nil) :: Users.User.t()
    def seed_users(organization \\ nil) do
      organization = get_organization(organization)

      {:ok, en} = Repo.fetch_by(Language, %{label_locale: "English"})

      utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

      create_contact_user(
        {organization, en, utc_now},
        {"NGO Staff", "919820112345", ["staff"]}
      )

      create_contact_user(
        {organization, en, utc_now},
        {"NGO Manager", "9101234567890", ["manager"]}
      )

      create_contact_user(
        {organization, en, utc_now},
        {"NGO Admin", "919999988888", ["admin"]}
      )

      {_, user} =
        create_contact_user(
          {organization, en, utc_now},
          {"NGO Person who left", "919988776655", ["none"]}
        )

      Repo.put_current_user(user)
      user
    end

    @doc false
    @spec seed_groups(Organization.t() | nil) :: nil
    def seed_groups(organization \\ nil) do
      organization = get_organization(organization)

      Repo.insert!(%Group{
        label: "Default Group",
        is_restricted: false,
        organization_id: organization.id
      })

      Repo.insert!(%Group{
        label: "Restricted Group",
        is_restricted: true,
        organization_id: organization.id
      })
    end

    defp add_to_group(contacts, group, organization, size) do
      contacts
      |> Enum.take(size)
      |> Enum.each(fn c ->
        Repo.insert!(%Groups.ContactGroup{
          contact_id: c.id,
          group_id: group.id,
          organization_id: organization.id
        })
      end)
    end

    @doc false
    @spec seed_group_contacts(Organization.t() | nil) :: :ok
    def seed_group_contacts(organization \\ nil) do
      organization = get_organization(organization)

      [_glific_admin | remainder] =
        Contacts.list_contacts(%{filter: %{organization_id: organization.id}})

      [g1, g2 | _] = Groups.list_groups(%{filter: %{organization_id: organization.id}})

      add_to_group(remainder, g1, organization, 7)
      add_to_group(remainder, g2, organization, -7)
    end

    @doc false
    @spec seed_group_messages(Organization.t() | nil) :: nil
    def seed_group_messages(organization \\ nil) do
      organization = get_organization(organization)

      [g1, g2 | _] = Glific.Groups.list_groups(%{filter: %{organization_id: organization.id}})

      do_seed_group_messages(g1, organization, 0)
      do_seed_group_messages(g2, organization, 2)
    end

    defp do_seed_group_messages(group, organization, time_shift) do
      {:ok, sender} =
        Repo.fetch_by(
          Contact,
          %{name: "NGO Main Account", organization_id: organization.id}
        )

      group = group |> Repo.preload(:contacts)

      group.contacts
      |> Enum.each(fn contact ->
        message_obj(group, sender, contact, organization)
        |> Repo.insert!()
      end)

      message_obj(group, sender, sender, organization)
      |> Map.merge(%{group_id: group.id})
      |> Repo.insert!()

      Repo.update!(
        Ecto.Changeset.change(group, %{
          last_communication_at:
            Timex.shift(DateTime.utc_now(), seconds: time_shift) |> DateTime.truncate(:second)
        })
      )
    end

    defp message_obj(group, sender, receiver, organization) do
      %Message{
        body: "#{group.label} message body",
        flow: :outbound,
        type: :text,
        bsp_message_id: Faker.String.base64(10),
        bsp_status: :enqueued,
        sender_id: sender.id,
        receiver_id: receiver.id,
        contact_id: receiver.id,
        organization_id: organization.id
      }
    end

    @doc false
    @spec seed_session_templates(Organization.t() | nil) :: nil
    def seed_session_templates(organization \\ nil) do
      organization = get_organization(organization)
      [en | _] = Settings.list_languages(%{filter: %{label: "english"}})
      [hi | _] = Settings.list_languages(%{filter: %{label: "hindi"}})

      translations = %{
        hi.id => %{
          body:
            " अब आप नीचे दिए विकल्पों में से एक का चयन करके {{1}} के साथ समाप्त होने वाले खाते के लिए अपना खाता शेष या मिनी स्टेटमेंट देख सकते हैं। | [अकाउंट बैलेंस देखें] | [देखें मिनी स्टेटमेंट]",
          language_id: hi.id,
          number_parameters: 1
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Account Balance",
        type: :text,
        shortcode: "account_balance",
        is_hsm: true,
        number_parameters: 1,
        language_id: en.id,
        translations: translations,
        organization_id: organization.id,
        status: "REJECTED",
        category: "ACCOUNT_UPDATE",
        example:
          "You can now view your Account Balance or Mini statement for Account ending with [003] simply by selecting one of the options below. | [View Account Balance] | [View Mini Statement]",
        # spaces are important here, since gupshup pattern matches on it
        body:
          "You can now view your Account Balance or Mini statement for Account ending with {{1}} simply by selecting one of the options below. | [View Account Balance] | [View Mini Statement]",
        uuid: Ecto.UUID.generate()
      })

      translations = %{
        hi.id => %{
          body:
            "नीचे दिए गए लिंक से अपना {{1}} टिकट डाउनलोड करें। | [वेबसाइट पर जाएं, https: //www.gupshup.io/developer/ {{2}}",
          language_id: hi.id,
          number_parameters: 2
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Movie Ticket",
        type: :text,
        shortcode: "movie_ticket",
        is_hsm: true,
        is_active: true,
        number_parameters: 2,
        language_id: en.id,
        organization_id: organization.id,
        translations: translations,
        status: "APPROVED",
        category: "TICKET_UPDATE",
        example:
          "Download your [message] ticket from the link given below. | [Visit Website,https://www.gupshup.io/developer/[message]]",
        body:
          "Download your {{1}} ticket from the link given below. | [Visit Website,https://www.gupshup.io/developer/{{2}}]",
        uuid: Ecto.UUID.generate()
      })

      translations = %{
        hi.id => %{
          body: " हाय {{1}}, \n कृपया बिल संलग्न करें।",
          language_id: hi.id,
          number_parameters: 1
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Personalized Bill",
        type: :text,
        shortcode: "personalized_bill",
        is_hsm: true,
        number_parameters: 1,
        language_id: en.id,
        organization_id: organization.id,
        translations: translations,
        status: "APPROVED",
        is_active: true,
        category: "ALERT_UPDATE",
        example: "Hi [Anil],\nPlease find the attached bill.",
        body: "Hi {{1}},\nPlease find the attached bill.",
        uuid: Ecto.UUID.generate()
      })

      translations = %{
        hi.id => %{
          body: "हाय {{1}}, \ n \ n आपके खाते की छवि {{2}} पर {{3}} द्वारा अद्यतन की गई थी।",
          language_id: hi.id,
          number_parameters: 3
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Account Update",
        type: :image,
        shortcode: "account_update",
        is_hsm: true,
        number_parameters: 3,
        translations: translations,
        language_id: en.id,
        organization_id: organization.id,
        status: "PENDING",
        category: "ALERT_UPDATE",
        body: "Hi {{1}},\n\nYour account image was updated on {{2}} by {{3}} with above",
        example:
          "Hi [Anil],\n\nYour account image was updated on [19th December] by [Saurav] with above",
        uuid: Ecto.UUID.generate()
      })

      translations = %{
        hi.id => %{
          body: " हाय {{1}}, \n कृपया बिल संलग्न करें।",
          language_id: hi.id,
          number_parameters: 1
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Bill",
        type: :text,
        shortcode: "bill",
        is_hsm: true,
        number_parameters: 1,
        language_id: en.id,
        organization_id: organization.id,
        translations: translations,
        status: "PENDING",
        category: "ALERT_UPDATE",
        body: "Hi {{1}},\nPlease find the attached bill.",
        example: "Hi [Anil],\nPlease find the attached bill.",
        uuid: Ecto.UUID.generate()
      })
    end

    @doc false
    @spec seed_group_users(Organization.t() | nil) :: nil
    def seed_group_users(organization \\ nil) do
      organization = get_organization(organization)

      [u1, u2 | _] = Users.list_users(%{filter: %{organization_id: organization.id}})
      [g1, g2 | _] = Groups.list_groups(%{filter: %{organization_id: organization.id}})

      Repo.insert!(%Groups.UserGroup{
        user_id: u1.id,
        group_id: g1.id,
        organization_id: organization.id
      })

      Repo.insert!(%Groups.UserGroup{
        user_id: u2.id,
        group_id: g1.id,
        organization_id: organization.id
      })

      Repo.insert!(%Groups.UserGroup{
        user_id: u1.id,
        group_id: g2.id,
        organization_id: organization.id
      })
    end

    @doc false
    @spec seed_test_flows(Organization.t() | nil) :: nil
    def seed_test_flows(organization \\ nil) do
      organization = get_organization(organization)

      test_flow =
        Repo.insert!(%Flow{
          name: "Test Workflow",
          keywords: ["test"],
          version_number: "13.1.0",
          uuid: "defda715-c520-499d-851e-4428be87def6",
          organization_id: organization.id
        })

      definition =
        File.read!(Path.join(:code.priv_dir(:glific), "data/flows/" <> "test.json"))
        |> Jason.decode!()

      Repo.insert!(%FlowRevision{
        definition: definition,
        flow_id: test_flow.id,
        status: "published",
        organization_id: organization.id
      })
    end

    @doc false
    @spec seed_flow_labels(Organization.t() | nil) :: {integer(), nil}
    def seed_flow_labels(organization \\ nil) do
      organization = get_organization(organization)

      flow_labels = [
        %{name: "Poetry"},
        %{name: "Visual Arts"},
        %{name: "Theatre"},
        %{name: "Understood"},
        %{name: "Not Understood"},
        %{name: "Interesting"},
        %{name: "Boring"},
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
      Repo.insert_all(FlowLabel, flow_labels, on_conflict: :raise)
    end

    @doc false
    @spec seed_flows(Organization.t() | nil) :: :ok
    def seed_flows(organization \\ nil) do
      organization = get_organization(organization)

      uuid_map = %{
        preference: "63397051-789d-418d-9388-2ef7eb1268bb",
        outofoffice: "af8a0aaa-dd10-4eee-b3b8-e59530e2f5f7",
        activity: "b050c652-65b5-4ccf-b62b-1e8b3f328676",
        feedback: "6c21af89-d7de-49ac-9848-c9febbf737a5",
        optout: "bc1622f8-64f8-4b3d-b767-bb6bbfb65104",
        survey: "8333fce2-63d3-4849-bfd9-3543eb8b0430",
        help: "3fa22108-f464-41e5-81d9-d8a298854429"
      }

      data = [
        {"Preference Workflow", ["preference"], uuid_map.preference, false, "preference.json"},
        {"Out of Office Workflow", ["outofoffice"], uuid_map.outofoffice, false,
         "out_of_office.json"},
        {"Survey Workflow", ["survey"], uuid_map.survey, false, "survey.json"}
      ]

      SeedsFlows.add_flow(organization, data, uuid_map)
    end

    @doc false
    @spec seed_flow_results(Organization.t() | nil) :: :ok
    def seed_flow_results(organization \\ nil) do
      {:ok, contact1} =
        Repo.fetch_by(
          Contact,
          %{name: "Adelle Cavin", organization_id: organization.id}
        )

      {:ok, contact2} =
        Repo.fetch_by(
          Contact,
          %{name: "Margarita Quinteros", organization_id: organization.id}
        )

      {:ok, contact3} =
        Repo.fetch_by(
          Contact,
          %{name: "Chrissy Cron", organization_id: organization.id}
        )

      {:ok, flow1} =
        Repo.fetch_by(
          Flow,
          %{name: "Survey Workflow", organization_id: organization.id}
        )

      {:ok, flow2} =
        Repo.fetch_by(
          Flow,
          %{name: "Preference Workflow", organization_id: organization.id}
        )

      0..10
      |> Enum.each(fn _ ->
        create_flow_results(
          Enum.random([contact1, contact2, contact3]),
          Enum.random([flow1, flow2]),
          organization.id
        )
      end)

      :ok
    end

    defp create_flow_results(contact, flow, org_id) do
      Repo.insert!(%FlowResult{
        results: get_results(),
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        flow_version: 1,
        organization_id: org_id
      })
    end

    defp get_results do
      Enum.random([
        %{language: %{input: Enum.random(0..10), category: "EngLish"}},
        %{language: %{input: Enum.random(0..10), category: "Hindi"}},
        %{optin: %{input: Enum.random(0..10), category: "Optin"}},
        %{help: %{input: Enum.random(0..10), category: "Optin"}},
        %{preference: %{input: Enum.random(0..10), category: "Video"}},
        %{preference: %{input: Enum.random(0..10), category: "Image"}},
        %{preference: %{input: Enum.random(0..10), category: "Audio"}}
      ])
    end

    @spec get_organization(Organization.t() | nil) :: Organization.t()
    defp get_organization(organization \\ nil) do
      if is_nil(organization),
        do: seed_organizations(),
        else: organization
    end

    @doc false
    @spec seed_billing(Organization.t()) :: nil
    def seed_billing(organization) do
      Repo.insert!(%Billing{
        name: "Billing name",
        stripe_customer_id: "test_customer_id",
        email: "Billing person email",
        currency: "inr",
        organization_id: organization.id,
        is_active: true,
        stripe_subscription_id: "test_subscription_id",
        stripe_subscription_items: %{price_1IdZbfEMShkCsLFn8TF0NLPO: "test_monthly_id"}
      })
    end

    @doc false
    @spec hsm_templates(Organization.t()) :: nil
    def hsm_templates(organization) do
      [hi | _] = Settings.list_languages(%{filter: %{label: "hindi"}})
      [en | _] = Settings.list_languages(%{filter: %{label: "english"}})

      translations = %{
        hi.id => %{
          body: " मुझे खेद है कि मैं कल आपकी चिंताओं का जवाब देने में सक्षम नहीं था, लेकिन मैं अब आपकी सहायता करने में प्रसन्न हूं।
          यदि आप इस चर्चा को जारी रखना चाहते हैं, तो कृपया 'हां' के साथ उत्तर दें।",
          language_id: hi.id,
          number_parameters: 0
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Missed Message Apology",
        type: :text,
        shortcode: "missed_message",
        is_hsm: true,
        number_parameters: 0,
        language_id: en.id,
        organization_id: organization.id,
        body: """
        I'm sorry that I wasn't able to respond to your concerns yesterday but I’m happy to assist you now.
        If you’d like to continue this discussion, please reply with ‘yes’
        """,
        translations: translations,
        status: "PENDING",
        category: "ALERT_UPDATE",
        uuid: Ecto.UUID.generate()
      })

      translations = %{
        hi.id => %{
          body: "{{1}} के लिए आपका OTP {{2}} है। यह {{3}} के लिए मान्य है।",
          example: "[अनिल को आदाता के रूप में जोड़ना] के लिए आपका OTP [1234] है। यह [15 मिनट] के लिए मान्य है।",
          language_id: hi.id,
          status: "APPROVED",
          label: "OTP Message",
          uuid: "98c7dec4-f05a-4a76-a25a-f7a50d821f27",
          number_parameters: 3,
          category: "ACCOUNT_UPDATE",
          type: :text
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "OTP Message",
        type: :text,
        shortcode: "otp",
        is_hsm: true,
        number_parameters: 3,
        language_id: en.id,
        organization_id: organization.id,
        translations: translations,
        status: "REJECTED",
        category: "ALERT_UPDATE",
        body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
        example:
          "Your OTP for [adding Anil as a payee] is [1234]. This is valid for [15 minutes].",
        uuid: Ecto.UUID.generate()
      })

      translations = %{
        hi.id => %{
          body:
            " कृपया फोन नंबर @ contact.phone के साथ पंजीकरण करने के लिए लिंक पर क्लिक करें @ global.registration.url",
          language_id: hi.id,
          number_parameters: 0
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "User Registration",
        body: """
        Please click on the link to register with the phone number @contact.phone
        @global.registration.url
        """,
        example: """
        Please click on the link to register with the phone number @contact.phone
        [https://www.gupshup.io/developer/register]
        """,
        type: :text,
        shortcode: "user-registration",
        is_reserved: true,
        language_id: en.id,
        translations: translations,
        status: "REJECTED",
        category: "ALERT_UPDATE",
        organization_id: organization.id,
        number_parameters: 0,
        uuid: Ecto.UUID.generate()
      })
    end

    @doc """
    Function to populate some basic data that we need for the system to operate. We will
    split this function up into multiple different ones for test, dev and production
    """
    @spec seed :: nil
    def seed do
      organization = get_organization()

      Repo.put_organization_id(organization.id)

      seed_providers()

      seed_contacts(organization)

      seed_users(organization)

      seed_tag(organization)

      seed_session_templates(organization)

      seed_flow_labels(organization)

      seed_flows(organization)

      seed_flow_results(organization)

      seed_groups(organization)

      seed_group_contacts(organization)

      seed_group_users(organization)

      seed_group_messages(organization)

      seed_messages(organization)

      seed_messages_media(organization)

      hsm_templates(organization)
    end
  end
end
