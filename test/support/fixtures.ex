defmodule Glific.Fixtures do
  @moduledoc """
  A module for defining fixtures that can be used in tests.
  """
  alias Faker.{
    DateTime,
    Name,
    Phone
  }

  alias Glific.{
    Contacts,
    Messages,
    Settings,
    Tags
  }

  @doc false
  @spec contact_fixture(map()) :: Contacts.Contact.t()
  def contact_fixture(attrs \\ %{}) do
    language = language_fixture()

    valid_attrs = %{
      name: Name.name(),
      optin_time: DateTime.backward(1),
      optout_time: DateTime.backward(1),
      phone: Phone.EnUs.phone(),
      status: :valid,
      provider_status: :invalid,
      language_id: language.id
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
    sender = contact_fixture(attrs)
    receiver = contact_fixture(attrs)

    valid_attrs = %{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      provider_message_id: Faker.String.base64(10),
      provider_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id
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
  @spec tag_fixture(map()) :: Tags.Tag.t()
  def tag_fixture(attrs \\ %{}) do
    valid_attrs = %{
      label: "some label",
      description: "some description",
      locale: "en_US",
      is_active: true,
      is_reserved: true
    }

    language = language_fixture()

    {:ok, tag} =
      attrs
      |> Map.put(:language_id, language.id)
      |> Enum.into(valid_attrs)
      |> Tags.create_tag()

    tag
  end

  @doc false
  @spec message_tag_fixture(map()) :: Tags.MessageTag.t()
  def message_tag_fixture(attrs \\ %{}) do
    valid_attrs = %{
      message_id: message_fixture().id,
      tag_id: tag_fixture().id
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
    valid_attrs = %{
      contact_id: contact_fixture().id,
      tag_id: tag_fixture().id
    }

    {:ok, contact_tag} =
      attrs
      |> Enum.into(valid_attrs)
      |> Tags.create_contact_tag()

    contact_tag
  end
end
