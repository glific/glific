defmodule Glific.Fixtures do
  @moduledoc """
  A module for defining fixtures that can be used in tests.
  This module can be used with a list of fixtures to apply as parameter:
      use Glific.Fixtures, [:user]
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

  def contact_fixture(attrs \\ %{}) do
    valid_attrs = %{
      name: Name.name(),
      optin_time: DateTime.backward(1),
      optout_time: DateTime.backward(1),
      phone: Phone.EnUs.phone(),
      status: :valid,
      wa_id: Phone.EnUs.phone(),
      wa_status: :invalid
    }

    {:ok, contact} =
      attrs
      |> Enum.into(valid_attrs)
      |> Contacts.create_contact()

    contact
  end

  def message_fixture(attrs \\ %{}) do
    valid_attrs = %{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      wa_message_id: Faker.String.base64(10),
      wa_status: :enqueued,
      sender_id: contact_fixture().id,
      recipient_id: contact_fixture().id
    }

    {:ok, message} =
      attrs
      |> Enum.into(valid_attrs)
      |> Messages.create_message()

    message
  end

  def language_fixture(attrs \\ %{}) do
    valid_attrs = %{
      label: Faker.Lorem.word(),
      locale: Faker.Lorem.word(),
      is_active: true
    }

    {:ok, language} =
      attrs
      |> Enum.into(valid_attrs)
      |> Settings.create_language()

    language
  end

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
end
