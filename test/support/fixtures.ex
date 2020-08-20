defmodule Glific.Fixtures do
  @moduledoc """
  A module for defining fixtures that can be used in tests.
  """
  alias Faker.{
    DateTime,
    Person,
    Phone
  }

  alias Glific.{
    Contacts,
    Groups,
    Messages,
    Settings,
    Tags,
    Templates
  }

  @doc false
  @spec contact_fixture(map()) :: Contacts.Contact.t()
  def contact_fixture(attrs \\ %{}) do
    valid_attrs = %{
      name: Person.name(),
      optin_time: DateTime.backward(1),
      last_message_at: DateTime.backward(0),
      phone: Phone.EnUs.phone(),
      status: :valid,
      provider_status: :session_and_hsm
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
      shortcode: "somelabel",
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

  @doc false
  @spec session_template_fixture(map()) :: Templates.SessionTemplate.t()
  def session_template_fixture(attrs \\ %{}) do
    language = language_fixture()

    valid_attrs = %{
      label: "Default Template Label",
      shortcode: "default template",
      body: "Default Template",
      type: :text,
      language_id: language.id,
      uuid: Ecto.UUID.generate()
    }

    {:ok, session_template} =
      attrs
      |> Enum.into(valid_attrs)
      |> Templates.create_session_template()

    valid_attrs_2 = %{
      label: "Another Template Label",
      shortcode: "another template",
      body: "Another Template",
      type: :text,
      language_id: language.id,
      parent_id: session_template.id,
      uuid: "53008c3d-e619-4ec6-80cd-b9b2c89386dc"
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
      description: "default description"
    }

    {:ok, group} =
      attrs
      |> Enum.into(valid_attrs)
      |> Groups.create_group()

    %{
      label: "Default Group",
      is_restricted: false
    }
    |> Groups.create_group()

    %{
      label: "Restricted Group",
      is_restricted: true
    }
    |> Groups.create_group()

    group
  end

  @doc false
  @spec group_contacts_fixture :: [Groups.ContactGroup.t(), ...]
  def group_contacts_fixture do
    group_fixture()

    [c1, c2 | _] = Contacts.list_contacts()
    [g1, g2 | _] = Groups.list_groups()

    {:ok, cg1} =
      Groups.create_contact_group(%{
        contact_id: c1.id,
        group_id: g1.id
      })

    {:ok, cg2} =
      Groups.create_contact_group(%{
        contact_id: c2.id,
        group_id: g1.id
      })

    {:ok, cg3} =
      Groups.create_contact_group(%{
        contact_id: c1.id,
        group_id: g2.id
      })

    [cg1, cg2, cg3]
  end

  @doc false
  @spec contact_tags_fixture :: [Tags.ContactTag.t(), ...]
  def contact_tags_fixture do
    tag_fixture()

    [c1, c2 | _] = Contacts.list_contacts()
    [t1, t2 | _] = Tags.list_tags()

    {:ok, ct1} =
      Tags.create_contact_tag(%{
        contact_id: c1.id,
        tag_id: t1.id
      })

    {:ok, ct2} =
      Tags.create_contact_tag(%{
        contact_id: c2.id,
        tag_id: t1.id
      })

    {:ok, ct3} =
      Tags.create_contact_tag(%{
        contact_id: c1.id,
        tag_id: t2.id
      })

    [ct1, ct2, ct3]
  end
end
