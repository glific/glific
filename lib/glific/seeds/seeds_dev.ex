defmodule Glific.Seeds.SeedsDev do
  @moduledoc """
  Script for populating the database. We can call this from tests and/or /priv/repo
  """
  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.Flow,
    Flows.FlowRevision,
    Groups,
    Groups.Group,
    Messages.Message,
    Messages.MessageMedia,
    Partners.Organization,
    Partners.Provider,
    Repo,
    Settings,
    Settings.Language,
    Tags.Tag,
    Users
  }

  alias Faker.Lorem.Shakespeare

  @now DateTime.utc_now() |> DateTime.truncate(:second)

  @doc """
  Smaller functions to seed various tables. This allows the test functions to call specific seeder functions.
  In the next phase we will also add unseeder functions as we learn more of the test capabilities
  """
  @spec seed_tag(Organization.t() | nil) :: nil
  def seed_tag(organization \\ nil) do
    organization = get_organization(organization)

    [hi_in | _] = Settings.list_languages(%{filter: %{label: "hindi"}})
    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    Repo.insert!(%Tag{
      label: "This is for testing",
      shortcode: "testing-only",
      description: "Marking message for testing purpose in English Language",
      language: en_us,
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

    [hi_in | _] = Settings.list_languages(%{filter: %{label: "hindi"}})
    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    contacts = [
      %{
        phone: "917834811231",
        name: "Default receiver",
        language_id: hi_in.id,
        optin_time: @now,
        provider_status: :session_and_hsm
      },
      %{
        name: "Adelle Cavin",
        phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
        language_id: hi_in.id
      },
      %{
        name: "Margarita Quinteros",
        phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
        language_id: hi_in.id
      },
      %{
        name: "Chrissy Cron",
        phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210)),
        language_id: en_us.id
      }
    ]

    contact_entries =
      for contact_entry <- contacts do
        %{
          inserted_at: @now,
          updated_at: @now,
          organization_id: organization.id,
          last_message_at: @now,
          provider_status: :session
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
        url: "test_url",
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
  @spec seed_organizations(any() | nil) :: Organization.t() | nil
  def seed_organizations(_unused \\ nil) do
    Organization |> Ecto.Query.first() |> Repo.one()
  end

  @doc false
  @spec seed_messages(Organization.t() | nil) :: nil
  def seed_messages(organization \\ nil) do
    organization = get_organization(organization)

    {:ok, sender} =
      Repo.fetch_by(
        Contact,
        %{name: "Glific Admin", organization_id: organization.id}
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
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: "ZZZ message body for order test",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: "hindi",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver.id,
      receiver_id: sender.id,
      contact_id: receiver.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: "english",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver.id,
      receiver_id: sender.id,
      contact_id: receiver.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: "hola",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver.id,
      receiver_id: sender.id,
      contact_id: receiver.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver2.id,
      receiver_id: sender.id,
      contact_id: receiver2.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver3.id,
      receiver_id: sender.id,
      contact_id: receiver3.id,
      organization_id: organization.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver4.id,
      receiver_id: sender.id,
      contact_id: receiver4.id,
      organization_id: organization.id
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
  @spec seed_users(Organization.t() | nil) :: Users.User.t()
  def seed_users(organization \\ nil) do
    organization = get_organization(organization)

    password = "12345678"

    {:ok, en_us} = Repo.fetch_by(Language, %{label_locale: "English"})

    contact1 =
      Repo.insert!(%Contact{
        phone: "919820112345",
        name: "NGO Basic User 1",
        language_id: en_us.id,
        optin_time: @now,
        last_message_at: @now,
        organization_id: organization.id
      })

    contact2 =
      Repo.insert!(%Contact{
        phone: "919876543210",
        name: "NGO Admin",
        language_id: en_us.id,
        optin_time: @now,
        last_message_at: @now,
        organization_id: organization.id
      })

    Users.create_user(%{
      name: "NGO Basic User 1",
      phone: "919820112345",
      password: password,
      confirm_password: password,
      roles: ["staff"],
      contact_id: contact1.id,
      organization_id: organization.id
    })

    {:ok, user} =
      Users.create_user(%{
        name: "NGO Admin",
        phone: "919876543210",
        password: password,
        confirm_password: password,
        roles: ["admin"],
        contact_id: contact2.id,
        organization_id: organization.id
      })

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

  @doc false
  @spec seed_group_contacts(Organization.t()) :: nil
  def seed_group_contacts(organization) do
    [c1, c2 | _] = Contacts.list_contacts(%{filter: %{organization_id: organization.id}})
    [g1, g2 | _] = Groups.list_groups(%{filter: %{organization_id: organization.id}})

    Repo.insert!(%Groups.ContactGroup{
      contact_id: c2.id,
      group_id: g1.id
    })

    Repo.insert!(%Groups.ContactGroup{
      contact_id: c1.id,
      group_id: g1.id
    })

    Repo.insert!(%Groups.ContactGroup{
      contact_id: c2.id,
      group_id: g2.id
    })
  end

  @doc false
  @spec seed_group_users(Organization.t()) :: nil
  def seed_group_users(organization) do
    [u1, u2 | _] = Users.list_users(%{filter: %{organization_id: organization.id}})
    [g1, g2 | _] = Groups.list_groups(%{filter: %{organization_id: organization.id}})

    Repo.insert!(%Groups.UserGroup{
      user_id: u1.id,
      group_id: g1.id
    })

    Repo.insert!(%Groups.UserGroup{
      user_id: u2.id,
      group_id: g1.id
    })

    Repo.insert!(%Groups.UserGroup{
      user_id: u1.id,
      group_id: g2.id
    })
  end

  @doc false
  @spec seed_flows(Organization.t() | nil) :: nil
  def seed_flows(organization \\ nil) do
    organization = get_organization(organization)

    test_flow =
      Repo.insert!(%Flow{
        name: "Test Workflow",
        shortcode: "test",
        keywords: ["test"],
        version_number: "13.1.0",
        uuid: "defda715-c520-499d-851e-4428be87def6",
        organization_id: organization.id
      })

    Repo.insert!(%FlowRevision{
      definition: FlowRevision.default_definition(test_flow),
      flow_id: test_flow.id,
      status: "done"
    })

    sol_activity =
      Repo.insert!(%Flow{
        name: "SoL Activity",
        shortcode: "solactivity",
        keywords: ["solactivity"],
        version_number: "13.1.0",
        uuid: "b050c652-65b5-4ccf-b62b-1e8b3f328676",
        organization_id: organization.id
      })

    sol_activity_definition =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/sol_activity.json"))
      |> Jason.decode!()

    sol_activity_definition =
      Map.merge(sol_activity_definition, %{
        "name" => sol_activity.name,
        "uuid" => sol_activity.uuid
      })

    Repo.insert!(%FlowRevision{
      definition: sol_activity_definition,
      flow_id: sol_activity.id,
      status: "done"
    })

    sol_feedback =
      Repo.insert!(%Flow{
        name: "SoL Feedback",
        shortcode: "solfeedback",
        keywords: ["solfeedback"],
        version_number: "13.1.0",
        uuid: "6c21af89-d7de-49ac-9848-c9febbf737a5",
        organization_id: organization.id
      })

    sol_feedback_definition =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/sol_feedback.json"))
      |> Jason.decode!()

    sol_feedback_definition =
      Map.merge(sol_feedback_definition, %{
        "name" => sol_feedback.name,
        "uuid" => sol_feedback.uuid
      })

    Repo.insert!(%FlowRevision{
      definition: sol_feedback_definition,
      flow_id: sol_feedback.id,
      status: "done"
    })
  end

  @spec get_organization(Organization.t() | nil) :: Organization.t()
  defp get_organization(organization \\ nil) do
    if is_nil(organization),
      do: seed_organizations(),
      else: organization
  end

  @doc """
  Function to populate some basic data that we need for the system to operate. We will
  split this function up into multiple different ones for test, dev and production
  """
  @spec seed :: nil
  def seed do
    organization = get_organization()

    seed_providers()

    seed_contacts(organization)

    seed_users(organization)

    seed_tag(organization)

    seed_messages(organization)

    seed_messages_media()

    seed_flows(organization)

    seed_groups(organization)

    seed_group_contacts(organization)

    seed_group_users(organization)
  end
end
