defmodule Glific.Fixtures do
  @moduledoc """
  A module for defining fixtures that can be used in tests.
  This module can be used with a list of fixtures to apply as parameter:
      use Glific.Fixtures, [:user]
  """

  alias Glific.Contacts.Contact
  alias Glific.{
    Contacts,
    Messages,
    Settings,
    Tags
  }

  def contact_fixture(attrs \\ %{}) do
        valid_attrs %{
          name: Faker.Name.name(),
          optin_time: Faker.DateTime.backward(1),
          optout_time: Faker.DateTime.backward(1),
          phone: Faker.Phone.EnUs.phone(),
          status: :valid,
          wa_id: Faker.Phone.EnUs.phone(),
          wa_status: :invalid
        }

        {:ok, contact} =
          attrs
          |> Enum.into(valid_attrs)
          |> Contacts.create_contact()
        contact
  end

  def message_fixture(attrs \\ %{}) do
      sender = contact_fixture()
      ricipient = contact_fixture()
      valid_attrs = {
        body: Faker.Lorem.sentence(),
        flow: :inbound,
        type: :text,
        wa_message_id: Faker.Lorem.characters(10),
        wa_status: :enqueued,
        sender_id: contact_fixture().id,
        ricipient_id: contact_fixture().id
      }

      {:ok, message} =
        attrs
        |> Enum.into(valid_attrs)
        |> Messages.create_message()

      message
  end

  def language_fixture(attrs \\ %{}) do
    valid_attrs %{
      label: Faker.mlocale(),
      locale: Faker.locale(),
      is_active: true
    }

    {:ok, language} =
      attrs
      |> Enum.into(valid_attrs)
      |> Settings.create_language()
    language
  end

  def tag_fixture(attrs \\ %{}) do
    language = language_fixture()
      {:ok, tag} =
        attrs
        |> Map.put(:language_id, language.id)
        |> Enum.into(@valid_attrs)
        |> Tags.create_tag()
      tag
  end

end
