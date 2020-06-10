defmodule Glific.Seeds do
  @moduledoc """
  Script for populating the database. We can call this from tests and/or /priv/repo
  """
  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Messages.MessageMedia,
    Partners.Organization,
    Partners.Provider,
    Repo,
    Settings.Language,
    Tags.Tag
  }

  @doc """
  Smaller functions to seed various tables. This allows the test functions to call specific seeder functions.
  In the next phase we will also add unseeder functions as we learn more of the test capabilities
  """
  @spec seed_language() :: {Language.t(), Language.t()}
  def seed_language do
    en_us =
      Repo.insert!(%Language{
        label: "English (United States)",
        locale: "en_US"
      })

    hi_in =
      Repo.insert!(%Language{
        label: "Hindi (India)",
        locale: "hi_IN"
      })

    {en_us, hi_in}
  end

  @doc false
  @spec seed_tag({Language.t(), Language.t()}) :: nil
  def seed_tag({en_us, _hi_in}) do
    message_tags_mt = Repo.insert!(%Tag{label: "Messages", language: en_us})
    message_tags_ct = Repo.insert!(%Tag{label: "Contacts", language: en_us})

    # Intent of message
    Repo.insert!(%Tag{label: "Compliments", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "Good Bye", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "Greeting", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "Thank You", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "Welcome", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    # Status of Message
    Repo.insert!(%Tag{label: "Critical", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "Important", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "Read", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "Spam", language: en_us, parent_id: message_tags_mt.id},
      is_reserved: 1
    )

    # Type of Contact
    Repo.insert!(%Tag{label: "Parrent", language: en_us, parent_id: message_tags_ct.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "Participant", language: en_us, parent_id: message_tags_ct.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "User", language: en_us, parent_id: message_tags_ct.id},
      is_reserved: 1
    )

    Repo.insert!(%Tag{label: "This is for testing", language: en_us})
  end

  @doc false
  @spec seed_contacts :: {Contact.t()}
  def seed_contacts do
    Repo.insert!(%Contact{phone: "917834811114", name: "Default Sender"})
    default_contact = Repo.insert!(%Contact{phone: "917834811231", name: "Default receiver"})

    Repo.insert!(%Contact{
      name: "Adelle Cavin",
      phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210))
    })

    Repo.insert!(%Contact{
      name: "Margarita Quinteros",
      phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210))
    })

    Repo.insert!(%Contact{
      name: "Chrissy Cron",
      phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210))
    })

    Repo.insert!(%Contact{
      name: "Hailey Wardlaw",
      phone: Integer.to_string(Enum.random(123_456_789..9_876_543_210))
    })

    {default_contact}
  end

  @doc false
  @spec seed_providers :: {Provider.t()}
  def seed_providers do
    default_provider =
      Repo.insert!(%Provider{
        name: "Default Provider",
        url: "test_url",
        api_end_point: "test"
      })

    Repo.insert!(%Provider{
      name: "gupshup",
      url: "test_url_1",
      api_end_point: "test"
    })

    Repo.insert!(%Provider{
      name: "twilio",
      url: "test_url_2",
      api_end_point: "test"
    })

    {default_provider}
  end

  @doc false
  @spec seed_organizations({Provider.t()}, {Contact.t()}) :: nil
  def seed_organizations({default_provider}, {default_contact}) do
    Repo.insert!(%Organization{
      name: "Default Organization",
      display_name: "Default Organization",
      contact_name: "Test",
      contact_id: default_contact.id,
      email: "test@glific.org",
      provider_id: default_provider.id,
      provider_key: "random",
      provider_number: Integer.to_string(Enum.random(123_456_789..9_876_543_210))
    })

    Repo.insert!(%Organization{
      name: "Slam Out Loud",
      display_name: "Slam Out Loud",
      contact_name: "Jigyasa and Gaurav",
      email: "jigyasa@glific.org",
      provider_id: default_provider.id,
      provider_key: "random",
      provider_number: Integer.to_string(Enum.random(123_456_789..9_876_543_210))
    })
  end

  @doc false
  @spec seed_messages :: nil
  def seed_messages do
    {:ok, sender} = Repo.fetch_by(Contact, %{name: "Default Sender"})
    {:ok, receiver} = Repo.fetch_by(Contact, %{name: "Default receiver"})

    Repo.insert!(%Message{
      body: "default message body",
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id
    })

    Repo.insert!(%Message{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id
    })

    Repo.insert!(%Message{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id
    })

    Repo.insert!(%Message{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id
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

  @doc """
  Function to populate some basic data that we need for the system to operate. We will
  split this function up into multiple different ones for test, dev and production
  """
  @spec seed :: nil
  def seed do
    {en_us, hi_in} = seed_language()

    seed_tag({en_us, hi_in})

    {default_contact} = seed_contacts()

    {default_provider} = seed_providers()

    seed_organizations({default_provider}, {default_contact})

    seed_messages()

    seed_messages_media()
  end
end
