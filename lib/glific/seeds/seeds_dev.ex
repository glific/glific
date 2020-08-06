defmodule Glific.Seeds.SeedsDev do
  @moduledoc """
  Script for populating the database. We can call this from tests and/or /priv/repo
  """
  alias Glific.{
    Contacts.Contact,
    Flows.Flow,
    Flows.FlowRevision,
    Groups.Group,
    Messages.Message,
    Messages.MessageMedia,
    Partners.Provider,
    Repo,
    Settings,
    Tags.Tag,
    Users
  }

  alias Faker.Lorem.Shakespeare

  @doc """
  Smaller functions to seed various tables. This allows the test functions to call specific seeder functions.
  In the next phase we will also add unseeder functions as we learn more of the test capabilities
  """
  @spec seed_tag :: nil
  def seed_tag do
    [hi_in | _] = Settings.list_languages(%{filter: %{label: "hindi"}})
    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    Repo.insert!(%Tag{label: "This is for testing", language: en_us})
    Repo.insert!(%Tag{label: "यह परीक्षण के लिए है", language: hi_in})
  end

  @doc false
  @spec seed_contacts :: {integer(), nil}
  def seed_contacts do
    [hi_in | _] = Settings.list_languages(%{filter: %{label: "hindi"}})
    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    contacts = [
      %{phone: "917834811231", name: "Default receiver", language_id: hi_in.id},
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

    inserted_time = DateTime.utc_now() |> DateTime.truncate(:second)

    contact_entries =
      for contact_entry <- contacts do
        contact_entry
        |> Map.put(:inserted_at, inserted_time)
        |> Map.put(:updated_at, inserted_time)
        |> Map.put(:last_message_at, inserted_time)
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
  @spec seed_organizations(Provider.t()) :: nil
  def seed_organizations(_default_provider) do
  end

  @doc false
  @spec seed_messages :: nil
  def seed_messages do
    {:ok, sender} = Repo.fetch_by(Contact, %{name: "Glific Admin"})
    {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Default receiver"})
    {:ok, receiver2} = Repo.fetch_by(Contact, %{name: "Adelle Cavin"})
    {:ok, receiver3} = Repo.fetch_by(Contact, %{name: "Margarita Quinteros"})
    {:ok, receiver4} = Repo.fetch_by(Contact, %{name: "Chrissy Cron"})

    Repo.insert!(%Message{
      body: "Default message body",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: "ZZZ message body for order test",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: "hindi",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver.id,
      receiver_id: sender.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: "english",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver.id,
      receiver_id: sender.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: "hola",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver.id,
      receiver_id: sender.id,
      contact_id: receiver.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver2.id,
      receiver_id: sender.id,
      contact_id: receiver2.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver3.id,
      receiver_id: sender.id,
      contact_id: receiver3.id
    })

    Repo.insert!(%Message{
      body: Shakespeare.hamlet(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: receiver4.id,
      receiver_id: sender.id,
      contact_id: receiver4.id
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
  @spec seed_users :: Users.User.t()
  def seed_users do
    password = "12345678"

    Users.create_user(%{
      name: "NGO Basic User 1",
      phone: "919820112345",
      password: password,
      confirm_password: password,
      roles: ["staff"]
    })

    Users.create_user(%{
      name: "NGO Admin",
      phone: "919876543210",
      password: password,
      confirm_password: password,
      roles: ["admin"]
    })
  end

  @doc false
  @spec seed_groups :: {Group.t()}
  def seed_groups do
    Repo.insert!(%Group{
      label: "Default Group",
      is_restricted: false
    })

    Repo.insert!(%Group{
      label: "Restricted Group",
      is_restricted: true
    })
  end

  @doc false
  @spec seed_flows :: nil
  def seed_flows do
    test_flow =
      Repo.insert!(%Flow{
        name: "Test Workflow",
        shortcode: "test",
        version_number: "13.1.0",
        uuid: "defda715-c520-499d-851e-4428be87def6"
      })

    Repo.insert!(%FlowRevision{
      definition: FlowRevision.default_definition(test_flow),
      flow_id: test_flow.id
    })

    timed_flow =
      Repo.insert!(%Flow{
        name: "Timed Workflow",
        shortcode: "timed",
        version_number: "13.1.0",
        uuid: "8390ded3-06c3-4df4-b428-064666f085c7"
      })

    timed_flow_definition =
      File.read!(Path.join(:code.priv_dir(:glific), "data/flows/timed.json"))
      |> Jason.decode!()

    timed_flow_definition =
      Map.merge(timed_flow_definition, %{
        "name" => timed_flow.name,
        "uuid" => timed_flow.uuid
      })

    Repo.insert!(%FlowRevision{
      definition: timed_flow_definition,
      flow_id: timed_flow.id
    })

    sol_activity =
      Repo.insert!(%Flow{
        name: "SoL Activity",
        shortcode: "solactivity",
        version_number: "13.1.0",
        uuid: "b050c652-65b5-4ccf-b62b-1e8b3f328676"
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
      flow_id: sol_activity.id
    })

    sol_feedback =
      Repo.insert!(%Flow{
        name: "SoL Feedback",
        shortcode: "solfeedback",
        version_number: "13.1.0",
        uuid: "6c21af89-d7de-49ac-9848-c9febbf737a5"
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
      flow_id: sol_feedback.id
    })
  end

  @doc """
  Function to populate some basic data that we need for the system to operate. We will
  split this function up into multiple different ones for test, dev and production
  """
  @spec seed :: nil
  def seed do
    default_provider = seed_providers()

    seed_organizations(default_provider)

    seed_contacts()

    seed_users()

    seed_tag()

    seed_messages()

    seed_messages_media()

    seed_flows()
  end
end
