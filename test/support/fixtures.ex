defmodule Glific.Fixtures do
  @moduledoc """
  A module for defining fixtures that can be used in tests.
  """

  import Ecto.Query, warn: false

  alias GlificWeb.Flows

  alias Faker.{
    DateTime,
    Person,
    Phone
  }

  alias Glific.{
    AccessControl,
    AccessControl.Permission,
    AccessControl.Role,
    Contacts,
    Contacts.ContactsField,
    Extensions.Extension,
    Flows,
    Flows.ContactField,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowLabel,
    Flows.WebhookLog,
    Groups,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroups,
    Groups.WAGroupsCollection,
    Groups.WaGroupsCollections,
    Mails.MailLog,
    MessageConversations,
    Messages,
    Messages.MessageConversation,
    Messages.MessageMedia,
    Notifications,
    Notifications.Notification,
    Partners,
    Partners.Billing,
    Partners.Organization,
    Partners.Provider,
    Profiles.Profile,
    Providers.Maytapi.Message,
    Registrations,
    Registrations.Registration,
    Repo,
    Saas.ConsultingHour,
    Settings,
    Sheets,
    Sheets.Sheet,
    Tags,
    Templates,
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates,
    Templates.SessionTemplate,
    Triggers,
    Triggers.Trigger,
    Users,
    WAGroup.WAManagedPhone,
    WAGroup.WAMessage,
    WAManagedPhones,
    WAMessages,
    WaPoll,
    WhatsappForms,
    WhatsappForms.WhatsappForm
  }

  @valid_attrs %{
    flow_id: 1,
    flow_uuid: Ecto.UUID.generate(),
    uuid_map: %{},
    node_uuid: Ecto.UUID.generate()
  }
  @doc """
  temp function for test to get org id. use sparingly
  """
  @spec get_org_id :: integer
  def get_org_id do
    organization = Organization |> Ecto.Query.first() |> Repo.one(skip_organization_id: true)
    organization.id
  end

  @doc false
  @spec contact_fixture(map()) :: Contacts.Contact.t()
  def contact_fixture(attrs \\ %{}) do
    valid_attrs = %{
      name: Person.name(),
      optin_time: DateTime.backward(1),
      optin_status: true,
      last_message_at: DateTime.backward(0),
      phone: Phone.EnUs.phone(),
      status: :valid,
      bsp_status: :session_and_hsm,
      organization_id: get_org_id(),
      language_id: 1
    }

    {:ok, contact} =
      attrs
      |> Enum.into(valid_attrs)
      |> Contacts.create_contact()

    contact
  end

  @doc false
  @spec message_fixture(map()) :: Messages.Message.t()
  def message_fixture(attrs \\ %{}) do
    sender_id =
      if attrs[:sender_id],
        do: attrs.sender_id,
        else: contact_fixture(attrs).id

    receiver_id =
      if attrs[:receiver_id],
        do: attrs.receiver_id,
        else: contact_fixture(attrs).id

    valid_attrs = %{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      bsp_message_id: Faker.String.base64(10),
      bsp_status: :enqueued,
      sender_id: sender_id,
      receiver_id: receiver_id,
      contact_id: receiver_id,
      organization_id: get_org_id()
    }

    {:ok, message} =
      attrs
      |> Enum.into(valid_attrs)
      |> Messages.create_message()

    message
  end

  @doc false
  @spec language_fixture(map()) :: Settings.Language.t()
  def language_fixture(attrs \\ %{}) do
    valid_attrs = %{
      label: Faker.Lorem.word(),
      label_locale: Faker.Lorem.word(),
      locale: Faker.Lorem.word(),
      is_active: true
    }

    {:ok, language} =
      attrs
      |> Enum.into(valid_attrs)
      |> Settings.language_upsert()

    language
  end

  @doc false
  @spec organization_fixture(map()) :: Organization.t()
  def organization_fixture(attrs \\ %{}) do
    contact =
      if Map.get(attrs, :contact_id),
        do: Contacts.get_contact!(attrs.contact_id),
        else: contact_fixture()

    {:ok, bsp} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

    valid_attrs = %{
      name: "Fixture Organization",
      is_active: true,
      is_approved: true,
      status: :active,
      shortcode: "fixture_org_shortcode",
      email: "replace@idk.org",
      last_communication_at: DateTime.backward(0),
      bsp_id: bsp.id,
      default_language_id: 1,
      contact_id: contact.id,
      active_language_ids: [1],
      out_of_office: %{
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
    }

    {:ok, organization} =
      attrs
      |> Enum.into(valid_attrs)
      |> Partners.create_organization()

    contact = Map.put(contact, :organization_id, organization.id)

    attrs = %{
      organization_id: organization.id,
      contact_id: contact.id
    }

    _user = user_fixture(attrs)

    Application.put_env(
      :glific,
      String.to_atom("provider_key_#{organization.id}"),
      "This is a fake key"
    )

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "gupshup_enterprise",
      keys: %{
        url: "test_url",
        handler: "Glific.Providers.Gupshup.Enterprise.Message",
        worker: "Glific.Providers.Gupshup.Enterprise.Worker",
        bsp_limit: 60
      },
      secrets: %{
        hsm_user_id: "Please enter your HSM account user id here",
        hsm_password: "Please enter your HSM account password here",
        two_way_user_id: "Please enter your two way account user id here",
        two_way_password: "Please enter your two way account password here"
      },
      is_active: false
    })

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "gupshup",
      keys: %{
        url: "test_url",
        handler: "Glific.Providers.Gupshup.Message",
        worker: "Glific.Providers.Gupshup.Worker",
        bsp_limit: 60
      },
      secrets: %{
        api_key: "Please enter your key here",
        app_name: "Please enter your App Name here",
        app_id: "Please enter app_id"
      },
      is_active: true
    })

    # ensure we get the triggered values in this refresh
    organization = Partners.get_organization!(organization.id)

    # lets store the organization in the cache
    Partners.fill_cache(organization)

    organization
  end

  @doc false
  @spec tag_fixture(map()) :: Tags.Tag.t()
  def tag_fixture(attrs) do
    valid_attrs = %{
      label: "some label",
      shortcode: "somelabel",
      description: "some fixed description",
      locale: "en",
      is_active: true,
      is_reserved: true
    }

    attrs = Map.merge(valid_attrs, attrs)
    language = language_fixture()

    {:ok, tag} =
      attrs
      |> Map.put_new(:language_id, language.id)
      |> Tags.create_tag()

    tag
  end

  @doc false
  @spec flow_label_fixture(map()) :: FlowLabel.t()
  def flow_label_fixture(attrs) do
    attrs = Map.merge(%{name: "Test Flow label"}, attrs)

    {:ok, flow_label} =
      attrs
      |> FlowLabel.create_flow_label()

    flow_label
  end

  @doc false
  @spec message_tag_fixture(map()) :: Tags.MessageTag.t()
  def message_tag_fixture(attrs) do
    valid_attrs = %{
      message_id: message_fixture(attrs).id,
      tag_id: tag_fixture(attrs).id
    }

    {:ok, message_tag} =
      attrs
      |> Enum.into(valid_attrs)
      |> Tags.create_message_tag()

    message_tag
  end

  @doc false
  @spec contact_tag_fixture(map()) :: Tags.ContactTag.t()
  def contact_tag_fixture(attrs \\ %{}) do
    contact = contact_fixture(attrs)

    valid_attrs = %{
      contact_id: contact.id,
      tag_id: tag_fixture(attrs).id,
      organization_id: contact.organization_id
    }

    {:ok, contact_tag} =
      attrs
      |> Enum.into(valid_attrs)
      |> Tags.create_contact_tag()

    contact_tag
  end

  @doc false
  @spec session_template_fixture(map()) :: SessionTemplate.t()
  def session_template_fixture(attrs \\ %{}) do
    language = language_fixture()

    valid_attrs = %{
      label: "Default Template Label",
      shortcode: "default_template",
      body: "Default Template",
      type: :text,
      language_id: language.id,
      organization_id: get_org_id()
    }

    {:ok, session_template} =
      attrs
      |> Enum.into(valid_attrs)
      |> Templates.create_session_template()

    uuid = Ecto.UUID.generate()

    valid_attrs_2 = %{
      label: "Another Template Label",
      shortcode: "another template",
      body: "Another Template",
      type: :text,
      language_id: language.id,
      parent_id: session_template.id,
      uuid: uuid,
      bsp_id: uuid,
      organization_id: get_org_id()
    }

    {:ok, _session_template} =
      valid_attrs_2
      |> Templates.create_session_template()

    session_template
  end

  @doc false
  @spec group_fixture(map()) :: Groups.Group.t()
  def group_fixture(attrs \\ %{}) do
    valid_attrs = %{
      label: "Poetry group",
      description: "default description",
      organization_id: get_org_id()
    }

    {:ok, group} =
      attrs
      |> Enum.into(valid_attrs)
      |> Groups.create_group()

    %{
      label: "Default Group",
      is_restricted: false,
      organization_id: get_org_id()
    }
    |> Groups.create_group()

    %{
      label: "Restricted Group",
      is_restricted: true,
      organization_id: get_org_id()
    }
    |> Groups.create_group()

    group
  end

  @doc false
  @spec contact_group_fixture(map()) :: Groups.ContactGroup.t()
  def contact_group_fixture(attrs) do
    valid_attrs = %{
      contact_id: contact_fixture(attrs).id,
      group_id: group_fixture(attrs).id
    }

    {:ok, contact_group} =
      attrs
      |> Enum.into(valid_attrs)
      |> Groups.create_contact_group()

    contact_group
  end

  @doc false
  @spec contact_user_group_fixture(map()) :: {Groups.ContactGroup.t(), Groups.UserGroup.t()}
  def contact_user_group_fixture(attrs) do
    valid_attrs = %{
      contact_id: contact_fixture(attrs).id,
      group_id: group_fixture(attrs).id
    }

    {:ok, contact_group} =
      attrs
      |> Enum.into(valid_attrs)
      |> Groups.create_contact_group()

    user = user_fixture(attrs)

    valid_attrs = %{
      user_id: user.id,
      group_id: contact_group.group_id
    }

    {:ok, user_group} =
      attrs
      |> Enum.into(valid_attrs)
      |> Groups.create_user_group()

    {contact_group, Map.put(user_group, :user, user)}
  end

  @doc false
  @spec group_contacts_fixture(map()) :: [Groups.ContactGroup.t(), ...]
  def group_contacts_fixture(attrs) do
    attrs = %{filter: attrs, opts: %{order: :asc}}

    group_fixture(attrs)

    [_glific_admin, c1, c2 | _] = Contacts.list_contacts(attrs)
    [g1, g2 | _] = Groups.list_groups(attrs)

    {:ok, cg1} =
      Groups.create_contact_group(%{
        contact_id: c1.id,
        group_id: g1.id,
        organization_id: attrs.filter.organization_id
      })

    {:ok, cg2} =
      Groups.create_contact_group(%{
        contact_id: c2.id,
        group_id: g1.id,
        organization_id: attrs.filter.organization_id
      })

    {:ok, cg3} =
      Groups.create_contact_group(%{
        contact_id: c1.id,
        group_id: g2.id,
        organization_id: attrs.filter.organization_id
      })

    [cg1, cg2, cg3]
  end

  @doc false
  @spec contact_tags_fixture(map()) :: [Tags.ContactTag.t(), ...]
  def contact_tags_fixture(attrs) do
    tag_fixture(attrs)

    attrs = %{filter: attrs, opts: %{order: :asc}}

    [_glific_admin, c1, c2 | _] = Contacts.list_contacts(attrs)
    [t1, t2 | _] = Tags.list_tags(attrs)

    {:ok, ct1} =
      Tags.create_contact_tag(%{
        contact_id: c1.id,
        tag_id: t1.id,
        organization_id: c1.organization_id
      })

    {:ok, ct2} =
      Tags.create_contact_tag(%{
        contact_id: c2.id,
        tag_id: t1.id,
        organization_id: c1.organization_id
      })

    {:ok, ct3} =
      Tags.create_contact_tag(%{
        contact_id: c1.id,
        tag_id: t2.id,
        organization_id: c1.organization_id
      })

    [ct1, ct2, ct3]
  end

  @doc false
  @spec template_tag_fixture(map()) :: Tags.TemplateTag.t()
  def template_tag_fixture(attrs \\ %{}) do
    tag = tag_fixture(attrs)
    template = session_template_fixture(attrs)

    valid_attrs = %{
      template_id: template.id,
      tag_id: tag.id
    }

    {:ok, template_tag} =
      attrs
      |> Enum.into(valid_attrs)
      |> Tags.create_template_tag()

    template_tag
  end

  @doc """
  Creates WhatsApp form fixture for tests.
  """
  @spec whatsapp_form_fixture :: {:ok, WhatsappForm.t()} | {:error, any()}
  def whatsapp_form_fixture do
    user = Repo.get_current_user()

    attrs = %{
      name: "sign_up_form",
      description: "Simple signup flow to collect name and email",
      status: "draft",
      categories: [:sign_up, :lead_generation],
      organization_id: get_org_id(),
      google_sheet_url: nil,
      meta_flow_id: "meta_flow_1234"
    }

    with {:ok, whatsapp_form} <- WhatsappForms.do_create_whatsapp_form(attrs),
         {:ok, revision} <- WhatsappForms.create_whatsapp_form_revision(whatsapp_form, user) do
      WhatsappForms.update_revision_id(whatsapp_form.id, revision.id)
    end
  end

  @doc false
  @spec flow_fixture(map()) :: Flows.Flow.t()
  def flow_fixture(attrs \\ %{}) do
    valid_attrs = %{
      name: "Test Flow",
      keywords: ["test_keyword"],
      flow_type: :message,
      version_number: "13.1.0",
      organization_id: get_org_id()
    }

    {:ok, flow} =
      attrs
      |> Enum.into(valid_attrs)
      |> Flows.create_flow()

    flow
  end

  @doc false
  @spec user_fixture(map()) :: Users.User.t()
  def user_fixture(attrs \\ %{}) do
    phone = Phone.EnUs.phone()

    valid_attrs = %{
      name: "some name",
      contact_id: contact_fixture(%{phone: phone}).id,
      phone: phone,
      password: "Secret1234!",
      password_confirmation: "Secret1234!",
      roles: ["admin"],
      language_id: 1,
      # This should be static for all the user fixtures
      organization_id: get_org_id()
    }

    {:ok, user} =
      attrs
      |> Enum.into(valid_attrs)
      |> Users.create_user()

    user
  end

  @doc false
  @spec otp_hsm_fixture() :: SessionTemplate.t()
  def otp_hsm_fixture do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "success",
              "token" => "new_partner_token",
              "template" => %{
                "elementName" => "verify_otp",
                "id" => "16e84186-97fa-454e-ac3b-8c9b94e53b4b",
                "languageCode" => "en_US",
                "status" => "APPROVED"
              }
            })
        }
    end)

    session_template_fixture(%{
      body: """
      Hello {{1}},

      Please find the verification number is {{2}} for resetting your account.
      """,
      shortcode: "verify_otp",
      is_hsm: true,
      category: "AUTHENTICATION",
      example: """
      Hello [Anil],

      Please find the verification number is [112233] for resetting your account.
      """,
      language_id: organization_fixture().default_language_id
    })
  end

  @doc false
  @spec message_media_fixture(map()) :: MessageMedia.t()
  def message_media_fixture(attrs) do
    {:ok, message_media} =
      %{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        flow: :inbound,
        caption: Faker.String.base64(10),
        is_template_media: false,
        organization_id: attrs.organization_id
      }
      |> Map.merge(attrs)
      |> Messages.create_message_media()

    message_media
  end

  @doc false
  @spec mock_validate_media(String.t()) :: any()
  def mock_validate_media(type \\ "image") do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          headers: %{
            "content-type" => "#{type}",
            "content-length" => "111"
          }
        }
    end)
  end

  @doc false
  @spec group_messages_fixture(map()) :: nil
  def group_messages_fixture(attrs) do
    [cg1, _cg2, cg3] = group_contacts_fixture(attrs)

    {:ok, group_1} =
      Repo.fetch_by(Groups.Group, %{id: cg1.group_id, organization_id: attrs.organization_id})

    {:ok, group_2} =
      Repo.fetch_by(Groups.Group, %{id: cg3.group_id, organization_id: attrs.organization_id})

    valid_attrs = %{
      body: "group message",
      flow: :outbound,
      type: :text,
      organization_id: attrs.organization_id
    }

    Messages.create_and_send_message_to_group(valid_attrs, group_1, :session)
    Messages.create_and_send_message_to_group(valid_attrs, group_2, :session)
    nil
  end

  @doc false
  @spec webhook_log_fixture(map()) :: WebhookLog.t()
  def webhook_log_fixture(attrs) do
    valid_attrs = %{
      url: "some url",
      method: "GET",
      request_headers: %{
        "Accept" => "application/json",
        "X-Glific-Signature" => "random signature"
      },
      request_json: %{},
      response_json: %{},
      status_code: 200,
      status: "Success"
    }

    contact = contact_fixture(attrs)
    flow = flow_fixture(Map.merge(attrs, %{keywords: [], name: Person.name()}))

    valid_attrs =
      valid_attrs
      |> Map.merge(attrs)
      |> Map.put(:contact_id, contact.id)
      |> Map.put(:flow_id, flow.id)
      |> Map.put(:organization_id, flow.organization_id)

    {:ok, webhook_log} = WebhookLog.create_webhook_log(valid_attrs)

    webhook_log
  end

  @doc false
  @spec trigger_fixture(map()) :: Trigger.t()
  def trigger_fixture(attrs) do
    valid_attrs = %{
      name: "test trigger",
      end_date: DateTime.forward(5),
      is_active: true,
      is_repeating: false,
      start_date: Timex.shift(Date.utc_today(), days: 1),
      start_time: Time.utc_now(),
      frequency: ["none"]
    }

    [g1 | _] = Groups.list_groups(attrs)

    flow_uuid = "cceb79e3-106c-4c29-98e5-a7f7a9a01dcd"
    {:ok, f1} = Repo.fetch_by(Flow, %{uuid: flow_uuid})

    valid_attrs =
      valid_attrs
      |> Map.merge(attrs)
      |> Map.put(:flow_id, f1.id)
      |> Map.put(:group_ids, [g1.id])
      |> Map.put(:organization_id, attrs.organization_id)

    {:ok, trigger} = Triggers.create_trigger(valid_attrs)

    trigger
  end

  @doc false
  @spec notification_fixture(map()) :: Notification.t()
  def notification_fixture(attrs) do
    [_glific_admin, contact | _] = Contacts.list_contacts(attrs)

    valid_attrs = %{
      category: "Message",
      message: "Cannot send message",
      severity: "Warning",
      organization_id: attrs.organization_id,
      entity: %{
        id: contact.id,
        name: contact.name,
        phone: contact.phone,
        bsp_status: contact.bsp_status,
        status: contact.status,
        last_message_at: contact.last_message_at
      }
    }

    valid_attrs =
      valid_attrs
      |> Map.merge(attrs)
      |> Map.put(:organization_id, attrs.organization_id)

    {:ok, notification} = Notifications.create_notification(valid_attrs)

    notification
  end

  @doc false
  @spec billing_fixture(map()) :: Billing.t()
  def billing_fixture(attrs) do
    valid_attrs = %{
      name: "some name",
      stripe_customer_id: "random_id",
      stripe_subscription_id: "random_subscription_id",
      email: "some email",
      currency: "inr"
    }

    {:ok, billing} =
      valid_attrs
      |> Map.merge(attrs)
      |> Map.put(:organization_id, attrs.organization_id)
      |> Billing.create_billing()

    billing
  end

  @doc false
  @spec consulting_hour_fixture(map()) :: ConsultingHour.t()
  def consulting_hour_fixture(attrs) do
    valid_attrs = %{
      participants: "Adam",
      organization_id: attrs.organization_id,
      organization_name: "Glific",
      staff: "Adelle Cavin",
      content: "GCS issue",
      when: DateTime.backward(2),
      duration: 10,
      is_billable: true
    }

    {:ok, consulting_hour} =
      valid_attrs
      |> Map.merge(attrs)
      |> ConsultingHour.create_consulting_hour()

    consulting_hour
  end

  @doc false
  @spec contacts_field_fixture(map()) :: ContactsField.t()
  def contacts_field_fixture(attrs) do
    valid_attrs = %{
      name: "Age",
      shortcode: "age",
      organization_id: attrs.organization_id
    }

    {:ok, contacts_field} =
      valid_attrs
      |> Map.merge(attrs)
      |> ContactField.create_contact_field()

    contacts_field
  end

  @doc false
  @spec extension_fixture(map()) :: Extension.t()
  def extension_fixture(attrs) do
    valid_attrs = %{
      code: """
      defmodule Glific.Test.ExtensionFixture do
        def default_phone() do
          %{phone: 9876543210}
        end
      end
      """,
      is_active: true,
      module: "Glific.Test.Extension",
      name: "Test extension",
      organization_id: attrs.organization_id
    }

    {:ok, extension} =
      valid_attrs
      |> Map.merge(attrs)
      |> Extension.create_extension()

    extension
  end

  @doc false
  @spec dg_contact_fixture(map()) :: Contacts.Contact.t()
  def dg_contact_fixture(
        %{
          enrolled_day: enrolled_day,
          next_flow_at: next_flow_at,
          initial_crop_day: initial_crop_day
        } = attrs
      ) do
    contact_fixture(attrs)
    |> ContactField.do_add_contact_field("total_days", "total_days", "10", "string")
    |> ContactField.do_add_contact_field(
      "enrolled_day",
      "enrolled_day",
      enrolled_day,
      "string"
    )
    |> ContactField.do_add_contact_field(
      "initial_crop_day",
      "initial_crop_day",
      initial_crop_day,
      "string"
    )
    |> ContactField.do_add_contact_field(
      "next_flow",
      "next_flow",
      "adoption",
      "string"
    )
    |> ContactField.do_add_contact_field(
      "next_flow_at",
      "next_flow_at",
      next_flow_at,
      "string"
    )
  end

  @doc false
  @spec flow_context_fixture(map()) :: FlowContext.t()
  def flow_context_fixture(attrs \\ %{}) do
    contact = contact_fixture()

    valid_attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      uuid_map: %{},
      node_uuid: Ecto.UUID.generate()
    }

    {:ok, flow_context} =
      attrs
      |> Map.put(:contact_id, contact.id)
      |> Map.put(:organization_id, contact.organization_id)
      |> Enum.into(valid_attrs)
      |> FlowContext.create_flow_context()

    flow_context
    |> Repo.preload(:contact)
    |> Repo.preload(:flow)
  end

  @doc false
  @spec interactive_fixture(map()) :: InteractiveTemplate.t()
  def interactive_fixture(attrs) do
    language = language_fixture()

    valid_attrs = %{
      label: "Quick Reply Fixture",
      type: :quick_reply,
      interactive_content: %{
        "type" => "quick_reply",
        "content" => %{
          "type" => "text",
          "text" => "Test glific quick reply?"
        },
        "options" => [
          %{
            "type" => "text",
            "title" => "Test 1"
          },
          %{
            "type" => "text",
            "title" => "Test 2"
          }
        ]
      },
      organization_id: attrs.organization_id,
      language_id: language.id
    }

    {:ok, interactive} =
      valid_attrs
      |> Map.merge(attrs)
      |> InteractiveTemplates.create_interactive_template()

    interactive
  end

  @doc false
  @spec mail_log_fixture(map()) :: MailLog.t()
  def mail_log_fixture(attrs) do
    valid_attrs = %{
      category: Faker.Lorem.word(),
      status: Faker.Lorem.word(),
      content: %{}
    }

    {:ok, mail_log} =
      valid_attrs
      |> Map.merge(attrs)
      |> MailLog.create_mail_log()

    mail_log
  end

  @doc """
  Generate a role.
  """
  @spec role_fixture(map()) :: Role.t()
  def role_fixture(attrs) do
    valid_attrs = %{
      description: "some description",
      is_reserved: false,
      label: "some label"
    }

    {:ok, role} =
      valid_attrs
      |> Map.merge(attrs)
      |> Map.put(:organization_id, attrs.organization_id)
      |> AccessControl.create_role()

    role
  end

  @doc """
  Generate a permission.
  """
  @spec permission_fixture(map()) :: Permission.t()
  def permission_fixture(attrs) do
    valid_attrs = %{
      entity: "some entity"
    }

    {:ok, permission} =
      valid_attrs
      |> Map.merge(attrs)
      |> Map.put(:organization_id, attrs.organization_id)
      |> AccessControl.create_permission()

    permission
  end

  @doc """
  Generate a profile.
  """
  @spec profile_fixture(map()) :: Profile.t()
  def profile_fixture(attrs \\ %{}) do
    contact = contact_fixture()

    valid_attrs = %{
      "contact_id" => contact.id,
      "organization_id" => contact.organization_id,
      "name" => "some name",
      "type" => "some type",
      "language_id" => 1
    }

    {:ok, profile} =
      valid_attrs
      |> Map.merge(attrs)
      |> Glific.Profiles.create_profile()

    Contacts.update_contact(contact, %{
      active_profile_id: profile.id,
      language_id: profile.language_id
    })

    profile
  end

  @doc """
  Generate a message conversation.
  """
  @spec message_conversation_fixture(map()) :: MessageConversation.t()
  def message_conversation_fixture(attrs \\ %{}) do
    message = message_fixture(attrs)

    valid_attrs = %{
      "organization_id" => message.organization_id,
      "message_id" => message.id,
      "conversation_id" => "some conversation id",
      "deduction_type" => "some deduction type",
      "payload" => %{},
      "is_billable" => false
    }

    {:ok, message_conversation} =
      valid_attrs
      |> Map.merge(attrs)
      |> MessageConversations.create_message_conversation()

    message_conversation
  end

  @doc """
  Generate a sheet conversations.
  """
  @spec sheet_fixture(map()) :: Sheet.t()
  def sheet_fixture(attrs \\ %{}) do
    Tesla.Mock.mock(fn
      %{
        method: :get,
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
      } ->
        %Tesla.Env{
          status: 200
        }

      %{
        method: :get,
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/export?format=csv&gid=0"
      } ->
        %Tesla.Env{
          body:
            "Key,Day,Message English,Video link,Message Hindi\r\n7/11/2022,1,Hi welcome to Glific. ,http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4,Glific में आपका स्वागत है।\r\n8/11/2022,2,Do you want to explore various programs that we have?,http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4,क्या आप हमारे पास मौजूद विभिन्न कार्यक्रमों का पता लगाना चाहते हैं?\r\n9/11/2022,3,Click on this link to know more about Glific,,Glific के बारे में अधिक जानने के लिए इस लिंक पर क्लिक करें\r\n10/11/2022,4,Please share your usecase,,कृपया अपना उपयोगकेस साझा करें",
          status: 200
        }

      %{
        method: :get,
        url:
          "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4"
      } ->
        %Tesla.Env{
          headers: [
            {"content-type", "video/mp4"},
            {"content-length", "3209581"}
          ],
          method: :get,
          status: 200
        }
    end)

    valid_attrs = %{
      label: "sample sheet",
      url:
        "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
      type: "READ",
      auto_sync: true
    }

    attrs = Map.merge(valid_attrs, attrs)

    {:ok, sheet} =
      attrs
      |> Sheets.create_sheet()

    sheet
  end

  @doc """
  Generate a wa_managed_phone.
  """
  @spec wa_managed_phone_fixture(map()) :: WAManagedPhone.t()
  def wa_managed_phone_fixture(attrs) do
    {:ok, contact} = Contacts.maybe_create_contact(Map.put(attrs, :phone, "917834811231"))

    {:ok, wa_managed_phone} =
      attrs
      |> Enum.into(%{
        label: "some label",
        phone: "9829627508",
        phone_id: 242,
        status: "loading",
        provider_id: 1,
        contact_id: contact.id
      })
      |> WAManagedPhones.create_wa_managed_phone()

    wa_managed_phone
  end

  @doc """
  Generate a wa_group.
  """
  @spec wa_group_fixture(map()) :: WAGroup.t()
  def wa_group_fixture(attrs) do
    {:ok, wa_group} =
      attrs
      |> Enum.into(%{
        label: "some label",
        bsp_id: "120363238104@g.us",
        wa_managed_phone_id: attrs.wa_managed_phone_id,
        organization_id: attrs.organization_id
      })
      |> WAGroups.create_wa_group()

    wa_group
  end

  @doc """
  temp function for test to get wa_managed_phone
  """
  @spec get_wa_managed_phone(non_neg_integer()) :: WAManagedPhone.t()
  def get_wa_managed_phone(organization_id) do
    Repo.fetch_by(WAManagedPhone, %{organization_id: organization_id})
    |> case do
      {:ok, wa_managed_phone} ->
        wa_managed_phone

      {:error, _error} ->
        wa_managed_phone_fixture(%{organization_id: organization_id})
    end
  end

  @doc """
  Generate a wa_message.
  """
  @spec wa_message_fixture(map()) :: WAMessage.t()
  def wa_message_fixture(attrs) do
    wa_managed_phone = get_wa_managed_phone(attrs.organization_id)

    {:ok, wa_message} =
      attrs
      |> Enum.into(%{
        body: Faker.Lorem.sentence(),
        flow: :inbound,
        type: :text,
        bsp_id: Faker.String.base64(10),
        contact_id: wa_managed_phone.contact_id,
        bsp_status: :enqueued,
        wa_managed_phone_id: wa_managed_phone.id,
        organization_id: attrs.organization_id
      })
      |> WAMessages.create_message()

    wa_message
  end

  @doc false
  @spec contact_wa_group_fixture(map()) :: ContactWAGroup.t()
  def contact_wa_group_fixture(attrs) do
    valid_attrs = %{
      contact_id: contact_fixture(attrs).id,
      wa_group_id: wa_group_fixture(attrs).id
    }

    {:ok, contact_wa_group} =
      attrs
      |> Enum.into(valid_attrs)
      |> ContactWAGroups.create_contact_wa_group()

    contact_wa_group
  end

  @doc false
  @spec wa_group_collection_message_fixture(map()) :: nil
  def wa_group_collection_message_fixture(attrs) do
    [wgc1, _wgc2, wgc3] = collection_wa_group_fixture(attrs)

    {:ok, group_1} = Repo.fetch_by(Groups.Group, %{id: wgc1.group_id})
    {:ok, group_2} = Repo.fetch_by(Groups.Group, %{id: wgc3.group_id})

    valid_attrs = %{
      message: "wa_group message",
      type: :text,
      organization_id: attrs.organization_id
    }

    Message.send_message_to_wa_group_collection(group_1, valid_attrs)
    Message.send_message_to_wa_group_collection(group_2, valid_attrs)
    nil
  end

  @doc false
  @spec collection_wa_group_fixture(map()) :: [WAGroupsCollection.t(), ...]
  def collection_wa_group_fixture(attrs) do
    wa_managed_phone = get_wa_managed_phone(attrs.organization_id)

    wg1 =
      wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    attrs = %{group_type: "WA", filter: attrs, opts: %{order: :asc}}

    g1 = group_fixture(attrs)

    {:ok, wgc1} =
      WaGroupsCollections.create_wa_groups_collection(%{
        group_id: g1.id,
        wa_group_id: wg1.id,
        organization_id: attrs.filter.organization_id
      })

    {:ok, wgc2} =
      WaGroupsCollections.create_wa_groups_collection(%{
        group_id: g1.id,
        wa_group_id: wg1.id,
        organization_id: attrs.filter.organization_id
      })

    {:ok, wgc3} =
      WaGroupsCollections.create_wa_groups_collection(%{
        group_id: g1.id,
        wa_group_id: wg1.id,
        organization_id: attrs.filter.organization_id
      })

    [wgc1, wgc2, wgc3]
  end

  @doc """
  Setup cache for partner token So that
  We don't need to mock the API calls
  """
  @spec set_bsp_partner_tokens(non_neg_integer()) :: :ok
  def set_bsp_partner_tokens(org_id \\ 1) do
    Glific.Caches.set(org_id, "partner_app_token", "Some_random_token", ttl: :timer.hours(22))
    Glific.Caches.set(org_id, "partner_token", "Some_random_token", ttl: :timer.hours(22))
    :ok
  end

  @doc false
  @spec registration_fixture :: Registration.t()
  def registration_fixture do
    valid_args = %{
      org_details: %{
        current_address: Faker.Lorem.paragraph(1..30),
        gstin: " 07AAAAA1234A124",
        name: Faker.Company.name(),
        registered_address: Faker.Lorem.paragraph(1..30)
      },
      signing_authority: %{
        name: Faker.Person.name(),
        email: Faker.Internet.email(),
        designation: "designation"
      },
      submitter: %{
        name: Faker.Person.name() |> String.slice(0, 10),
        email: Faker.Internet.email()
      },
      finance_poc: %{
        name: Faker.Person.name() |> String.slice(0, 10),
        email: Faker.Internet.email(),
        designation: "Sr Accountant",
        phone: Phone.PtBr.phone()
      },
      platform_details: %{
        app_name: "app_name",
        api_key: "api_key",
        phone: Phone.PtBr.phone()
      },
      billing_frequency: "yearly",
      organization_id: get_org_id()
    }

    {:ok, registration} = Registrations.create_registration(valid_args)
    registration
  end

  @doc false
  @spec wa_poll_fixture(map()) :: Glific.WAGroup.WaPoll.t()
  def wa_poll_fixture(attrs \\ %{}) do
    %{
      label: "Test Poll",
      organization_id: 1,
      allow_multiple_answer: true,
      poll_content: %{
        "options" => [
          %{"id" => 0, "name" => "Option 1", "voters" => [], "votes" => 0},
          %{"id" => 1, "name" => "Option 2", "voters" => [], "votes" => 0}
        ],
        "text" => "Poll question?"
      }
    }
    |> Map.merge(attrs)
    |> WaPoll.create_wa_poll()
    |> then(fn {:ok, wa_poll} -> wa_poll end)
  end

  @doc false
  @spec wa_flow_context_fixture(map()) :: FlowContext.t()
  def wa_flow_context_fixture(attrs \\ %{}) do
    wa_phone = wa_managed_phone_fixture(attrs)
    wa_group = wa_group_fixture(Map.put(attrs, :wa_managed_phone_id, wa_phone.id))

    {:ok, flow_context} =
      attrs
      |> Map.put(:wa_group_id, wa_group.id)
      |> Map.put(:organization_id, wa_group.organization_id)
      |> Enum.into(@valid_attrs)
      |> FlowContext.create_flow_context()

    flow_context
    |> Repo.preload(:wa_group)
    |> Repo.preload(:flow)
  end
end
