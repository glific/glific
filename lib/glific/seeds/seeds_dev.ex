if Code.ensure_loaded?(Faker) do
  defmodule Glific.Seeds.SeedsDev do
    @moduledoc """
    Script for populating the database. We can call this from tests and/or /priv/repo
    """

    alias Faker.Phone

    alias Glific.{
      AccessControl,
      AccessControl.Role,
      Contacts,
      Contacts.Contact,
      Contacts.ContactHistory,
      Flows.Flow,
      Flows.FlowLabel,
      Flows.FlowResult,
      Flows.FlowRevision,
      Flows.MessageBroadcast,
      Groups,
      Groups.Group,
      Groups.WAGroup,
      Groups.WAGroups,
      Groups.WAGroupsCollection,
      Messages.Message,
      Messages.MessageMedia,
      Notifications,
      Notifications.Notification,
      Partners.Billing,
      Partners.Organization,
      Partners.Provider,
      Repo,
      Seeds.SeedsFlows,
      Settings,
      Settings.Language,
      Stats.Stat,
      Tags.Tag,
      Templates.InteractiveTemplate,
      Templates.SessionTemplate,
      Users,
      WAGroup.WAManagedPhone,
      WAGroup.WAMessage,
      WAManagedPhones,
      WhatsappForms.WhatsappForm,
      WhatsappFormsRevisions
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
          bsp_status: :session_and_hsm,
          contact_type: "WABA"
        },
        %{
          name: "Adelle Cavin",
          phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
          language_id: hi_in.id,
          bsp_status: :session_and_hsm,
          optin_time: utc_now,
          optin_status: true,
          contact_type: "WABA"
        },
        %{
          name: "Margarita Quinteros",
          phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
          language_id: hi_in.id,
          bsp_status: :session_and_hsm,
          optin_time: utc_now,
          optin_status: true,
          contact_type: "WABA"
        },
        %{
          name: "Chrissy Cron",
          phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
          language_id: en.id,
          bsp_status: :session_and_hsm,
          optin_time: utc_now,
          optin_status: true,
          contact_type: "WABA"
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

      message =
        Repo.insert!(%Message{
          body: Shakespeare.hamlet(),
          flow: :outbound,
          type: :text,
          bsp_message_id: Faker.String.base64(10),
          bsp_status: :enqueued,
          sender_id: sender.id,
          receiver_id: receiver4.id,
          contact_id: receiver4.id,
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
        organization_id: organization.id,
        context_id: message.bsp_message_id,
        context_message_id: message.id
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
        flow: :inbound,
        caption: "default caption",
        is_template_media: false,
        organization_id: organization.id
      })

      Repo.insert!(%MessageMedia{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        flow: :inbound,
        caption: Faker.String.base64(10),
        is_template_media: false,
        organization_id: organization.id
      })

      Repo.insert!(%MessageMedia{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        flow: :outbound,
        caption: Faker.String.base64(10),
        is_template_media: false,
        organization_id: organization.id
      })

      Repo.insert!(%MessageMedia{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        flow: :outbound,
        caption: Faker.String.base64(10),
        is_template_media: false,
        organization_id: organization.id
      })
    end

    defp create_contact_user(
           {organization, en, utc_now},
           {name, phone, roles}
         ) do
      password = "Secret12345678!"

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

    @doc """
    Seeds sample WhatsApp Forms (Flows) for the given organization.
    These mimic Meta Playground JSON definitions.
    """
    @spec seed_whatsapp_forms(Organization.t() | nil) :: :ok
    def seed_whatsapp_forms(organization \\ nil) do
      organization = get_organization(organization)

      seed_sheets(organization)
      seed_users(organization)

      {:ok, sheet_1} =
        Repo.fetch_by(Sheet, %{
          label: "Responses Sheet",
          organization_id: organization.id
        })

      {:ok, sheet_2} =
        Repo.fetch_by(Sheet, %{
          label: "User Data Sheet",
          organization_id: organization.id
        })

      forms = [
        %{
          name: "sign_up_form",
          description: "Simple signup flow to collect name and email",
          meta_flow_id: "flow-9e3bf3f2-0c9f-4a8b-bf23-33b7e5d2fbb2",
          status: :published,
          categories: [:sign_up, :lead_generation],
          organization_id: organization.id
        },
        %{
          name: "contact_us_form",
          description: "Feedback and queries collection form",
          meta_flow_id: "flow-8f91de44-b123-482e-bb52-77f1c3a78df0",
          status: :draft,
          categories: [:contact_us],
          organization_id: organization.id
        },
        %{
          name: "feedback_form",
          description: "Inactive form for collecting customer satisfaction feedback",
          meta_flow_id: "flow-7a12cd90-c6e4-4e56-9a23-001f89b2a8b1",
          status: :inactive,
          definition: %{
            "version" => "1.0",
            "screens" => [
              %{
                "id" => "screen_1",
                "title" => "Feedback",
                "description" => "We’d love to hear your thoughts",
                "fields" => [
                  %{
                    "id" => "rating",
                    "label" => "Rate your experience (1-5)",
                    "type" => "number",
                    "required" => true
                  },
                  %{
                    "id" => "comments",
                    "label" => "Additional Comments",
                    "type" => "text",
                    "required" => false
                  }
                ],
                "actions" => [%{"type" => "submit", "label" => "Submit Feedback"}]
              }
            ]
          },
          categories: [:survey, :customer_support],
          organization_id: organization.id
        },
        %{
          name: "newsletter_subscription_form",
          description: "Draft form to collect email subscriptions for newsletters",
          meta_flow_id: "flow-2a73be22-0a11-4a6d-bb77-8c21df5cdb92",
          status: :draft,
          definition: %{
            "version" => "1.0",
            "screens" => [
              %{
                "id" => "screen_1",
                "title" => "Subscribe",
                "description" => "Join our newsletter to stay updated",
                "fields" => [
                  %{
                    "id" => "email",
                    "label" => "Email Address",
                    "type" => "email",
                    "required" => true
                  }
                ],
                "actions" => [%{"type" => "submit", "label" => "Subscribe"}]
              }
            ]
          },
          categories: [:customer_support],
          organization_id: organization.id
        },
        %{
          name: "event_registration_form",
          description: "Form for users to register for upcoming events or webinars",
          meta_flow_id: "flow-6c45ae11-8f76-4e9c-ae56-9f6d9a2b4a90",
          status: :published,
          definition: %{
            "version" => "1.0",
            "screens" => [
              %{
                "id" => "screen_1",
                "title" => "Event Registration",
                "description" => "Register for our upcoming event",
                "fields" => [
                  %{
                    "id" => "full_name",
                    "label" => "Full Name",
                    "type" => "text",
                    "required" => true
                  },
                  %{
                    "id" => "email",
                    "label" => "Email Address",
                    "type" => "email",
                    "required" => true
                  },
                  %{
                    "id" => "event_choice",
                    "label" => "Select Event",
                    "type" => "dropdown",
                    "required" => true,
                    "options" => ["Webinar", "Workshop", "Conference"]
                  }
                ],
                "actions" => [%{"type" => "submit", "label" => "Register"}]
              }
            ]
          },
          categories: [:customer_support],
          organization_id: organization.id
        }
      ]

      {:ok, user} = Repo.fetch_by(Users.User, %{name: "NGO Staff"})

      Enum.each(forms, fn form ->
        whatsapp_form = Repo.insert!(struct(WhatsappForm, form))

        {:ok, revision} =
          WhatsappFormsRevisions.create_revision(%{
            whatsapp_form_id: whatsapp_form.id,
            definition: Map.get(form, :definition, WhatsappFormsRevisions.default_definition()),
            user_id: user.id,
            organization_id: whatsapp_form.organization_id
          })

        whatsapp_form
        |> Ecto.Changeset.change(%{revision_id: revision.id})
        |> Repo.update!()
      end)
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

      # Group with collection of WA groups
      Repo.insert!(%Group{
        label: "Default WA Group Collection",
        is_restricted: false,
        organization_id: organization.id,
        group_type: "WA"
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

      [_g1, _g2, g3, g4 | _] = Groups.list_groups(%{filter: %{organization_id: organization.id}})

      add_to_group(remainder, g3, organization, 7)
      add_to_group(remainder, g4, organization, -7)
    end

    @doc false
    @spec seed_group_messages(Organization.t() | nil) :: nil
    def seed_group_messages(organization \\ nil) do
      organization = get_organization(organization)

      [_g1, _g2, g3, g4 | _] =
        Glific.Groups.list_groups(%{filter: %{organization_id: organization.id}})

      do_seed_group_messages(g3, organization, 0)
      do_seed_group_messages(g4, organization, 2)
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

    @template_id "32905118-9e03-4bf1-9edd-98323b4d3d38"
    @translated_template_id "a1d810f4-b102-446c-968c-10ff2f5c129f"

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
          number_parameters: 1,
          status: "APPROVED",
          uuid: Ecto.UUID.generate(),
          label: "Account Balance",
          example:
            " अब आप नीचे दिए विकल्पों में से एक का चयन करके [003] के साथ समाप्त होने वाले खाते के लिए अपना खाता शेष या मिनी स्टेटमेंट देख सकते हैं। | [अकाउंट बैलेंस देखें] | [देखें मिनी स्टेटमेंट]"
        }
      }

      Repo.insert!(%SessionTemplate{
        label: "Account Balance",
        type: :text,
        shortcode: "account_balance",
        is_hsm: true,
        is_active: true,
        number_parameters: 1,
        language_id: en.id,
        translations: translations,
        organization_id: organization.id,
        status: "APPROVED",
        category: "ACCOUNT_UPDATE",
        example:
          "You can now view your Account Balance or Mini statement for Account ending with [003] simply by selecting one of the options below.",
        # spaces are important here, since gupshup pattern matches on it
        body:
          "You can now view your Account Balance or Mini statement for Account ending with {{1}} simply by selecting one of the options below.",
        uuid: Ecto.UUID.generate(),
        button_type: "quick_reply",
        has_buttons: true,
        buttons: [
          %{"text" => "View Account Balance", "type" => "QUICK_REPLY"},
          %{"text" => "View Mini Statement", "type" => "QUICK_REPLY"}
        ]
      })

      translations = %{
        hi.id => %{
          body:
            "नीचे दिए गए लिंक से अपना {{1}} टिकट डाउनलोड करें। | [Visit Website, https://www.gupshup.io/developer/{{2}}",
          type: "text",
          uuid: @translated_template_id,
          label: "movie_ticket",
          status: "APPROVED",
          example:
            "नीचे दिए गए लिंक से अपना [मुददा] टिकट डाउनलोड करें। | [Visit Website, https://www.gupshup.io/developer/[issues-hin]",
          category: "MARKETING",
          language_id: 2,
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
        uuid: @template_id
      })

      Repo.insert!(%SessionTemplate{
        label: "Translated Movie Ticket",
        type: :text,
        shortcode: "movie_ticket",
        is_hsm: true,
        is_active: true,
        number_parameters: 2,
        language_id: hi.id,
        organization_id: organization.id,
        status: "APPROVED",
        category: "TICKET_UPDATE",
        body:
          "नीचे दिए गए लिंक से अपना {{1}} टिकट डाउनलोड करें। | [Visit Website, https://www.gupshup.io/developer/{{2}}",
        example:
          "नीचे दिए गए लिंक से अपना [मुददा] टिकट डाउनलोड करें। | [Visit Website, https://www.gupshup.io/developer/[issues-hin]",
        uuid: @translated_template_id
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
        category: "UTILITY",
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
        category: "UTILITY",
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
        category: "UTILITY",
        body: "Hi {{1}},\nPlease find the attached bill.",
        example: "Hi [Anil],\nPlease find the attached bill.",
        uuid: Ecto.UUID.generate()
      })

      Repo.insert!(%SessionTemplate{
        label: "File Update",
        type: :video,
        shortcode: "file_update",
        is_hsm: true,
        number_parameters: 1,
        translations: translations,
        language_id: en.id,
        organization_id: organization.id,
        status: "APPROVED",
        category: "UTILITY",
        body: "Hi {{1}},\n\nYour image file was updated today",
        example: "Hi [Anil],\n\nYour image file was updated today",
        uuid: Ecto.UUID.generate()
      })

      Repo.insert!(%SessionTemplate{
        label: "File reminder",
        type: :document,
        shortcode: "file_reminder",
        is_hsm: true,
        number_parameters: 1,
        translations: translations,
        language_id: en.id,
        organization_id: organization.id,
        status: "APPROVED",
        category: "UTILITY",
        body: "Hi {{1}},\n\nYour document file was updated today",
        example: "Hi [Anil],\n\nYour document file was updated today",
        uuid: Ecto.UUID.generate()
      })
    end

    @doc false
    @spec seed_group_users(Organization.t() | nil) :: nil
    def seed_group_users(organization \\ nil) do
      organization = get_organization(organization)

      [u1, u2 | _] = Users.list_users(%{filter: %{organization_id: organization.id}})
      [_g1, _g2, g3, g4 | _] = Groups.list_groups(%{filter: %{organization_id: organization.id}})

      Repo.insert!(%Groups.UserGroup{
        user_id: u1.id,
        group_id: g3.id,
        organization_id: organization.id
      })

      Repo.insert!(%Groups.UserGroup{
        user_id: u2.id,
        group_id: g3.id,
        organization_id: organization.id
      })

      Repo.insert!(%Groups.UserGroup{
        user_id: u1.id,
        group_id: g4.id,
        organization_id: organization.id
      })
    end

    @doc false
    @spec seed_user_roles(Organization.t() | nil) :: nil
    def seed_user_roles(organization \\ nil) do
      organization = get_organization(organization)

      [_u1, _u2, u3, u4, u5, u6 | _] =
        Users.list_users(%{filter: %{organization_id: organization.id}})

      [r1, r2, r3, r4 | _] = AccessControl.list_roles(%{organization_id: organization.id})

      Repo.insert!(%AccessControl.UserRole{
        user_id: u3.id,
        role_id: r2.id,
        organization_id: organization.id
      })

      Repo.insert!(%AccessControl.UserRole{
        user_id: u4.id,
        role_id: r3.id,
        organization_id: organization.id
      })

      Repo.insert!(%AccessControl.UserRole{
        user_id: u5.id,
        role_id: r1.id,
        organization_id: organization.id
      })

      Repo.insert!(%AccessControl.UserRole{
        user_id: u6.id,
        role_id: r4.id,
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

      definition = get_flow_definition("test")

      Repo.insert!(%FlowRevision{
        definition: definition,
        flow_id: test_flow.id,
        status: "published",
        organization_id: organization.id
      })

      import_flow =
        Repo.insert!(%Flow{
          name: "Import Workflow",
          keywords: ["importtest"],
          version_number: "13.1.0",
          uuid: "63a9c563-a735-4b7d-9890-b9298a2de406",
          organization_id: organization.id
        })

      definition = get_flow_definition("import")

      Repo.insert!(%FlowRevision{
        definition: definition,
        flow_id: import_flow.id,
        status: "published",
        organization_id: organization.id
      })

      wa_group_flow =
        Repo.insert!(%Flow{
          name: "Whatsapp Group",
          keywords: ["wagroup"],
          version_number: "13.2.0",
          uuid: "49f1a269-a505-467b-8aab-cf21eadcdd30",
          organization_id: organization.id
        })

      definition = get_flow_definition("wa_group")

      Repo.insert!(%FlowRevision{
        definition: definition,
        flow_id: wa_group_flow.id,
        status: "published",
        organization_id: organization.id
      })

      invalid_exp_flow =
        Repo.insert!(%Flow{
          name: "Invalid expression",
          keywords: ["ie"],
          version_number: "13.2.0",
          uuid: "5f85cc81-3893-4fbf-ab56-73421fbba05f",
          organization_id: organization.id
        })

      definition = get_flow_definition("invalid_expression")

      Repo.insert!(%FlowRevision{
        definition: definition,
        flow_id: invalid_exp_flow.id,
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
        help: "3fa22108-f464-41e5-81d9-d8a298854429",
        intent: "56c4d7c4-4884-45e2-b4f9-82ddc4553519",
        interactive: "b87dafcf-a316-4da6-b1f4-2714a199aab7",
        clear_var: "3ac6ec5e-041a-4b0f-9dad-9b2b9a9545ce",
        direct_gpt: "0d51efbb-a8b4-4c32-828c-47ac915da479",
        media: "0b2d5b19-bd94-44e0-b2e6-0ea7d7033de5"
      }

      data = [
        {"Preference Workflow", ["preference"], uuid_map.preference, false, "preference.json"},
        {"Out of Office Workflow", ["outofoffice"], uuid_map.outofoffice, false,
         "out_of_office.json"},
        {"Survey Workflow", ["survey"], uuid_map.survey, false, "survey.json"},
        {"Intent", ["intent"], uuid_map.intent, false, "intent.json"},
        {"Interactive", ["interactive"], uuid_map.interactive, false, "interactive.json"}
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
        stripe_customer_id: "test_cus_JIdQjmJcjq",
        email: "Billing person email",
        currency: "inr",
        organization_id: organization.id,
        is_active: true,
        stripe_subscription_id: "test_subscription_id",
        stripe_subscription_items: %{
          price_1IdZbfEMShkCsLFn8TF0NLPO: "test_monthly_id"
        }
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

      uuid = Ecto.UUID.generate()

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
        category: "UTILITY",
        uuid: uuid,
        bsp_id: uuid
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

      uuid = Ecto.UUID.generate()

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
        category: "AUTHENTICATION",
        body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
        example:
          "Your OTP for [adding Anil as a payee] is [1234]. This is valid for [15 minutes].",
        uuid: uuid,
        bsp_id: uuid
      })

      translations = %{
        hi.id => %{
          body:
            " कृपया फोन नंबर @ contact.phone के साथ पंजीकरण करने के लिए लिंक पर क्लिक करें @ global.registration.url",
          language_id: hi.id,
          number_parameters: 0
        }
      }

      uuid = Ecto.UUID.generate()

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
        category: "UTILITY",
        organization_id: organization.id,
        number_parameters: 0,
        uuid: uuid,
        bsp_id: uuid
      })
    end

    @doc false
    @spec seed_notification(Organization.t()) :: nil
    def seed_notification(organization) do
      Repo.insert!(%Notification{
        category: "Partner",
        message:
          "Disabling bigquery. Account does not have sufficient permissions to insert data to BigQuery.",
        severity: Notifications.types().critical,
        organization_id: organization.id,
        entity: %{
          id: 2,
          shortcode: "bigquery"
        }
      })

      Repo.insert!(%Notification{
        category: "Message",
        message: "Cannot send session message to contact, invalid bsp status.",
        severity: Notifications.types().warning,
        organization_id: organization.id,
        entity: %{
          id: 1,
          name: "Adelle Cavin",
          phone: "91987656789",
          bsp_status: "hsm",
          status: "valid",
          last_message_at: "2021-03-23T17:05:01Z",
          is_hsm: nil,
          flow_id: 1,
          group_id: nil
        }
      })

      Repo.insert!(%Notification{
        category: "Flow",
        message: "Cannot send session message to contact, invalid bsp status.",
        severity: Notifications.types().warning,
        organization_id: organization.id,
        entity: %{
          flow_id: 3,
          parent_id: 6,
          contact_id: 3,
          flow_uuid: "12c25af0-37a2-4a69-8e26-9cfd98cab5c6",
          name: "Preference Workflow"
        }
      })

      Repo.insert!(%Notification{
        category: "Templates",
        message: "Template Account balance has been approved",
        severity: Notifications.types().info,
        organization_id: organization.id,
        entity: %{
          id: 1,
          shortcode: "account_balance",
          label: "Account Balance",
          uuid: "98c7dec4-f05a-4a76-a25a-f7a50d821f27"
        }
      })

      Repo.insert!(%Notification{
        category: "Templates",
        message: "Template OTP Message has been rejected",
        severity: Notifications.types().info,
        organization_id: organization.id,
        entity: %{
          id: 9,
          shortcode: "otp",
          label: "OTP Message",
          uuid: "98c7dec4-f05a-4a76-a25a-f7a50d821f27"
        }
      })
    end

    @doc false
    @spec seed_stats(Organization.t()) :: list()
    def seed_stats(organization) do
      Repo.insert!(%Stat{
        period: "day",
        date: DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.to_date(),
        contacts: 20,
        active: 0,
        optin: 18,
        optout: 17,
        messages: 201,
        inbound: 120,
        outbound: 81,
        hsm: 20,
        flows_started: 25,
        flows_completed: 10,
        users: 7,
        hour: 0,
        organization_id: organization.id,
        conversations: 0,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      Enum.map(1..24, fn hour ->
        inbound = Enum.random(1..30)
        outbound = Enum.random(1..50)
        total = inbound + outbound

        date =
          DateTime.utc_now()
          |> Timex.shift(days: Enum.random(-1..-5//-1))
          |> DateTime.to_date()

        Repo.insert!(%Stat{
          period: "hour",
          date: date,
          contacts: Enum.random(0..20),
          active: Enum.random(0..5),
          optin: Enum.random(1..10),
          optout: Enum.random(1..5),
          messages: total,
          inbound: inbound,
          outbound: outbound,
          hsm: Enum.random(1..10),
          flows_started: Enum.random(1..25),
          flows_completed: Enum.random(1..10),
          users: Enum.random(1..5),
          hour: hour,
          organization_id: organization.id,
          conversations: Enum.random(1..10),
          inserted_at:
            DateTime.utc_now() |> DateTime.add(-hour, :hour) |> DateTime.truncate(:second)
        })
      end)
    end

    @doc false
    @spec seed_interactives(Organization.t() | nil) :: InteractiveTemplate.t()
    def seed_interactives(organization \\ nil) do
      organization = get_organization(organization)

      [en | _] = Settings.list_languages(%{filter: %{label: "english"}})

      [
        %{
          "type" => "quick_reply",
          "content" => %{
            "type" => "text",
            "header" => "Quick Reply Text",
            "text" => "Glific is a two way communication platform"
          },
          "options" => [
            %{
              "type" => "text",
              "title" => "Excited"
            },
            %{
              "type" => "text",
              "title" => "Very Excited"
            }
          ]
        },
        %{
          "type" => "quick_reply",
          "content" => %{
            "header" => "Quick Reply Image",
            "type" => "image",
            "url" => "https://picsum.photos/200/300",
            "text" => "body text"
          },
          "options" => [
            %{"type" => "text", "title" => "First"},
            %{"type" => "text", "title" => "Second"},
            %{"type" => "text", "title" => "Third"}
          ]
        },
        %{
          "type" => "quick_reply",
          "content" => %{
            "header" => "Quick Reply Document",
            "type" => "file",
            "url" => "http://enterprise.smsgupshup.com/doc/GatewayAPIDoc.pdf",
            "filename" => "Sample file"
          },
          "options" => [
            %{"type" => "text", "title" => "First"},
            %{"type" => "text", "title" => "Second"},
            %{"type" => "text", "title" => "Third"}
          ]
        },
        %{
          "type" => "quick_reply",
          "content" => %{
            "header" => "Quick Reply Video",
            "type" => "video",
            "url" => "http://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4",
            "text" => "Sample video"
          },
          "options" => [
            %{"type" => "text", "title" => "First"},
            %{"type" => "text", "title" => "Second"},
            %{"type" => "text", "title" => "Third"}
          ]
        }
      ]
      |> Enum.each(fn interactive_content ->
        Repo.insert!(%InteractiveTemplate{
          label: get_in(interactive_content, ["content", "header"]),
          type: :quick_reply,
          interactive_content: interactive_content,
          organization_id: organization.id,
          language_id: en.id,
          translations: %{
            "1" => interactive_content
          }
        })
      end)

      interactive_content_eng = %{
        "type" => "quick_reply",
        "content" => %{
          "header" => "Are you excited for *Glific*?",
          "type" => "text",
          "text" => "Glific comes with all new features"
        },
        "options" => [
          %{"type" => "text", "title" => "yes"},
          %{"type" => "text", "title" => "no"}
        ]
      }

      interactive_content_hin = %{
        "type" => "quick_reply",
        "content" => %{
          "header" => "आप ग्लिफ़िक के लिए कितने उत्साहित हैं?",
          "type" => "text",
          "text" => "ग्लिफ़िक सभी नई सुविधाओं के साथ आता है"
        },
        "options" => [
          %{"type" => "text", "title" => "हाँ"},
          %{"type" => "text", "title" => "ना"}
        ]
      }

      translation = %{
        "1" => interactive_content_eng,
        "2" => interactive_content_hin
      }

      Repo.insert!(%InteractiveTemplate{
        label: get_in(interactive_content_eng, ["content", "header"]),
        type: :quick_reply,
        interactive_content: interactive_content_eng,
        organization_id: organization.id,
        language_id: en.id,
        translations: translation
      })

      interactive_content = %{
        "type" => "list",
        "title" => "Interactive list",
        "body" => "Glific",
        "globalButtons" => [%{"type" => "text", "title" => "button text"}],
        "items" => [
          %{
            "title" => "Glific Features",
            "subtitle" => "first Subtitle",
            "options" => [
              %{
                "type" => "text",
                "title" => "Custom Flows",
                "description" => "Flow Editor for creating flows"
              },
              %{
                "type" => "text",
                "title" => "Analytic Reports",
                "description" => "DataStudio for report generation"
              },
              %{
                "type" => "text",
                "title" => "ML/AI",
                "description" => "Dialogflow for AI/ML"
              }
            ]
          },
          %{
            "title" => "Glific Usecases",
            "subtitle" => "some usecases of Glific",
            "options" => [
              %{
                "type" => "text",
                "title" => "Educational programs",
                "description" => "Sharing education content with school student"
              }
            ]
          },
          %{
            "title" => "Onboarded NGOs",
            "subtitle" => "List of NGOs onboarded",
            "options" => [
              %{
                "type" => "text",
                "title" => "SOL",
                "description" => "Slam Out Loud is a non-profit with a vision to change lives."
              }
            ]
          }
        ]
      }

      Repo.insert!(%InteractiveTemplate{
        label: get_in(interactive_content, ["title"]),
        type: :list,
        interactive_content: interactive_content,
        organization_id: organization.id,
        language_id: en.id,
        translations: %{
          "1" => interactive_content
        }
      })

      interactive_content = %{
        "type" => "location_request_message",
        "body" => %{
          "type" => "text",
          "text" => "please share your location"
        },
        "action" => %{
          "name" => "send_location"
        }
      }

      Repo.insert!(%InteractiveTemplate{
        label: "Send Location",
        type: :location_request_message,
        interactive_content: interactive_content,
        organization_id: organization.id,
        language_id: en.id,
        translations: %{
          "1" => interactive_content
        }
      })
    end

    @doc false
    @spec seed_optin_interactives(Organization.t() | nil) :: InteractiveTemplate.t()
    def seed_optin_interactives(organization \\ nil) do
      organization = get_organization(organization)
      [en | _] = Settings.list_languages(%{filter: %{label: "english"}})

      interactive_content = %{
        "type" => "quick_reply",
        "content" => %{
          "text" =>
            "Welcome to our NGO bot. Thank you for contacting us. To stay connected with us, kindly grant us permission to message you\n\nPress 👍 to give us permission. We promise to send you amazing content.\nPress 👎 if you'd rather message us when you need information.",
          "type" => "text",
          "header" => "Optin template"
        },
        "options" => [%{"type" => "text", "title" => "👍"}, %{"type" => "text", "title" => "👎"}]
      }

      interactive_content_hin = %{
        type: "quick_reply",
        content: %{
          text:
            "हमारे NGO बॉट में आपका स्वागत है। हमसे संपर्क करने के लिए धन्यवाद। हमारे साथ जुड़े रहने के लिए, कृपया हमें आपको संदेश भेजने की अनुमति दें\n\nहमें अनुमति देने के लिए 👍 दबाएं। हम आपको केवल महत्वपूर्ण जानकारी भेजने का वादा करते हैं।\n\nयदि आपको जानकारी की आवश्यकता होने पर आप हमें संदेश भेजना चाहते हैं तो 👎 दबाएं।",
          type: "text",
          header: "Optin template"
        },
        options: [
          %{type: "text", title: "👍"},
          %{type: "text", title: "👎"}
        ]
      }

      Repo.insert!(%InteractiveTemplate{
        label: get_in(interactive_content, ["content", "header"]),
        type: :quick_reply,
        interactive_content: interactive_content,
        organization_id: organization.id,
        language_id: en.id,
        send_with_title: false,
        translations: %{
          "1" => interactive_content,
          "2" => interactive_content_hin
        }
      })
    end

    @doc false
    @spec seed_contact_history(Organization.t()) :: ContactHistory.t()
    def seed_contact_history(organization) do
      {:ok, contact} =
        Repo.fetch_by(
          Contact,
          %{name: "Adelle Cavin", organization_id: organization.id}
        )

      {:ok, flow} =
        Repo.fetch_by(
          Flow,
          %{name: "Survey Workflow", organization_id: organization.id}
        )

      Repo.insert!(%ContactHistory{
        contact_id: contact.id,
        event_label: "Flow Started",
        event_type: "contact_flow_started",
        event_meta: %{
          context_id: 1,
          flow: %{
            id: flow.id,
            uuid: flow.uuid,
            name: flow.name
          }
        },
        organization_id: organization.id
      })

      Repo.insert!(%ContactHistory{
        contact_id: contact.id,
        event_label: "All contact flows are ended",
        event_type: "contact_flow_ended_all",
        event_meta: %{},
        organization_id: organization.id
      })
    end

    @doc false
    @spec seed_roles(Organization.t() | nil) :: Role.t()
    def seed_roles(organization \\ nil) do
      organization = get_organization(organization)

      Repo.insert!(%Role{
        label: "Admin",
        description: "Default Admin Role",
        is_reserved: true,
        organization_id: organization.id
      })

      Repo.insert!(%Role{
        label: "Staff",
        description: "Default Staff Role",
        is_reserved: true,
        organization_id: organization.id
      })

      Repo.insert!(%Role{
        label: "Manager",
        description: "Default Manager Role",
        is_reserved: true,
        organization_id: organization.id
      })

      Repo.insert!(%Role{
        label: "No access",
        description: "Default Role with no permissions",
        is_reserved: true,
        organization_id: organization.id
      })

      app_env = Application.get_env(:glific, :environment)
      trusted_env? = Glific.trusted_env?(app_env, organization.id)

      if trusted_env?,
        do:
          Repo.insert!(%Role{
            label: "Glific Admin",
            description: "Super Admin Role for Glific",
            is_reserved: true,
            organization_id: organization.id
          })
    end

    @doc false
    @spec seed_broadcast(Organization.t() | nil) :: MessageBroadcast.t()
    def seed_broadcast(organization) do
      [flow_1, flow_2 | _] = Glific.Flows.list_flows(%{organization_id: organization.id})
      [group | _] = Groups.list_groups(%{filter: %{organization_id: organization.id}})

      [message | _] =
        Glific.Messages.list_messages(%{filter: %{organization_id: organization.id}})

      [user | _] = Users.list_users(%{filter: %{organization_id: organization.id}})

      Repo.insert!(%MessageBroadcast{
        flow_id: flow_1.id,
        group_id: group.id,
        message_id: message.id,
        user_id: user.id,
        organization_id: organization.id,
        started_at: DateTime.utc_now() |> DateTime.add(-3, :hour) |> DateTime.truncate(:second),
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      Repo.insert!(%MessageBroadcast{
        flow_id: flow_2.id,
        group_id: group.id,
        message_id: message.id,
        user_id: user.id,
        organization_id: organization.id,
        started_at: DateTime.utc_now() |> DateTime.add(-2, :hour) |> DateTime.truncate(:second),
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end

    @doc false
    @spec seed_wa_managed_phones(Organization.t() | nil) :: {integer(), nil}
    def seed_wa_managed_phones(organization \\ nil) do
      organization = get_organization(organization)

      {:ok, contact_1} =
        Repo.fetch_by(
          Contact,
          %{name: "NGO Main Account", organization_id: organization.id}
        )

      {:ok, contact_2} =
        Repo.fetch_by(
          Contact,
          %{name: "Default receiver", organization_id: organization.id}
        )

      {:ok, contact_3} =
        Repo.fetch_by(
          Contact,
          %{name: "Adelle Cavin", organization_id: organization.id}
        )

      wa_managed_phones = [
        %{
          phone: Phone.EnUs.phone(),
          phone_id: Enum.random(1000..9999),
          contact_id: contact_1.id
        },
        %{
          phone: Phone.EnUs.phone(),
          phone_id: Enum.random(1000..9999),
          contact_id: contact_2.id
        },
        %{
          phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
          phone_id: Enum.random(1000..9999),
          contact_id: contact_3.id
        }
      ]

      wa_managed_phone_entries =
        for wa_managed_phone_entry <- wa_managed_phones do
          %{
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now(),
            organization_id: organization.id
          }
          |> Map.merge(wa_managed_phone_entry)
        end

      # seed wa_managed_phones
      Repo.insert_all(WAManagedPhone, wa_managed_phone_entries)
    end

    @doc false
    @spec seed_wa_groups(Organization.t() | nil) :: {integer(), nil}
    def seed_wa_groups(organization \\ nil) do
      organization = get_organization(organization)

      {:ok, contact_1} =
        Repo.fetch_by(
          Contact,
          %{name: "NGO Main Account", organization_id: organization.id}
        )

      {:ok, contact_2} =
        Repo.fetch_by(
          Contact,
          %{name: "Default receiver", organization_id: organization.id}
        )

      {:ok, contact_3} =
        Repo.fetch_by(
          Contact,
          %{name: "Adelle Cavin", organization_id: organization.id}
        )

      {:ok, wa_managed_phone_1} =
        Repo.fetch_by(
          WAManagedPhone,
          %{contact_id: contact_1.id, organization_id: organization.id}
        )

      {:ok, wa_managed_phone_2} =
        Repo.fetch_by(
          WAManagedPhone,
          %{contact_id: contact_2.id, organization_id: organization.id}
        )

      {:ok, wa_managed_phone_3} =
        Repo.fetch_by(
          WAManagedPhone,
          %{contact_id: contact_3.id, organization_id: organization.id}
        )

      wa_groups = [
        %{
          label: Faker.Team.name(),
          bsp_id: (:rand.uniform(1_000_000_000_000_000_000) |> to_string()) <> "@g.us",
          wa_managed_phone_id: wa_managed_phone_1.id
        },
        %{
          label: Faker.Team.name(),
          bsp_id: (:rand.uniform(1_000_000_000_000_000_000) |> to_string()) <> "@g.us",
          wa_managed_phone_id: wa_managed_phone_2.id
        },
        %{
          label: Faker.Team.name(),
          bsp_id: (:rand.uniform(1_000_000_000_000_000_000) |> to_string()) <> "@g.us",
          wa_managed_phone_id: wa_managed_phone_3.id
        }
      ]

      wa_group_entries =
        for wa_group_entry <- wa_groups do
          %{
            inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
            last_communication_at: DateTime.utc_now() |> DateTime.truncate(:second),
            organization_id: organization.id
          }
          |> Map.merge(wa_group_entry)
        end

      # seed wa_groups
      Repo.insert_all(WAGroup, wa_group_entries)
    end

    @doc false
    @spec seed_wa_messages(Organization.t() | nil) :: {integer(), nil}
    def seed_wa_messages(organization \\ nil) do
      organization = get_organization(organization)

      {:ok, contact_2} =
        Repo.fetch_by(
          Contact,
          %{name: "Default receiver", organization_id: organization.id}
        )

      [wa_managed_phone_1, wa_managed_phone_2 | _] =
        WAManagedPhones.list_wa_managed_phones(%{organization_id: organization.id})

      [wa_group_1, wa_group_2 | _] = WAGroups.list_wa_groups(%{organization_id: organization.id})

      wa_messages = [
        %{
          type: "text",
          bsp_id: Faker.String.base64(10),
          flow: "inbound",
          bsp_status: "received",
          contact_id: contact_2.id,
          status: "received",
          wa_managed_phone_id: wa_managed_phone_1.id,
          wa_group_id: wa_group_1.id,
          body: Shakespeare.hamlet()
        },
        %{
          type: "text",
          bsp_id: Faker.String.base64(10),
          flow: "inbound",
          bsp_status: "received",
          contact_id: contact_2.id,
          status: "received",
          wa_managed_phone_id: wa_managed_phone_1.id,
          wa_group_id: wa_group_1.id,
          body: Shakespeare.hamlet()
        },
        %{
          type: "text",
          bsp_id: Faker.String.base64(10),
          flow: "outbound",
          bsp_status: "delivered",
          contact_id: contact_2.id,
          status: "sent",
          wa_managed_phone_id: wa_managed_phone_2.id,
          wa_group_id: wa_group_2.id,
          body: Shakespeare.hamlet()
        },
        %{
          type: "text",
          bsp_id: Faker.String.base64(10),
          flow: "outbound",
          bsp_status: "delivered",
          contact_id: contact_2.id,
          status: "sent",
          wa_managed_phone_id: wa_managed_phone_2.id,
          wa_group_id: wa_group_2.id,
          body: "This is a DM message",
          is_dm: true
        }
      ]

      wa_messages_entries =
        for wa_messages_entry <- wa_messages do
          %{
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now(),
            organization_id: organization.id
          }
          |> Map.merge(wa_messages_entry)
        end

      # seed wa_messages
      Repo.insert_all(WAMessage, wa_messages_entries)
    end

    @doc false
    @spec seed_wa_group_collections(Organization.t() | nil) :: :ok
    def seed_wa_group_collections(organization \\ nil) do
      organization = get_organization(organization)
      wa_groups = WAGroups.list_wa_groups(%{filter: %{organization_id: organization.id}})

      [group] =
        Groups.list_groups(%{
          filter: %{organization_id: organization.id, label: "Default WA Group Collection"}
        })

      wa_groups
      |> Enum.take(2)
      |> Enum.each(fn wa_group ->
        Repo.insert!(%WAGroupsCollection{
          wa_group_id: wa_group.id,
          group_id: group.id,
          organization_id: organization.id
        })
      end)
    end

    @doc """
    Function to populate some basic data that we need for the system to operate. We will
    split this function up into multiple different ones for test, dev and production
    """
    @spec seed :: :ok
    def seed do
      organization = get_organization()

      Repo.put_organization_id(organization.id)

      seed_contacts(organization)

      seed_users(organization)

      seed_tag(organization)

      seed_session_templates(organization)

      seed_flow_labels(organization)

      seed_interactives(organization)

      seed_flows(organization)

      seed_flow_results(organization)

      seed_groups(organization)

      seed_group_contacts(organization)

      seed_group_users(organization)

      seed_group_messages(organization)

      seed_messages(organization)

      seed_messages_media(organization)

      hsm_templates(organization)

      seed_notification(organization)

      seed_contact_history(organization)

      seed_user_roles(organization)

      seed_stats(organization)

      seed_broadcast(organization)

      seed_wa_managed_phones(organization)

      seed_wa_groups(organization)

      seed_wa_messages(organization)

      seed_wa_group_collections(organization)
      :ok
    end

    @spec get_flow_definition(String.t()) :: map()
    defp get_flow_definition(flow_json_name) do
      :code.priv_dir(:glific)
      |> Path.join("data/flows/" <> "#{flow_json_name}.json")
      |> File.read!()
      |> Jason.decode!()
    end
  end
end
