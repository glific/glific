defmodule Glific.WAManagedPhonesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.WAGroup` context.
  """

  alias Glific.{
    Contacts,
    Groups.WAGroup,
    Groups.WAGroups,
    WAGroup.WAManagedPhone,
    WAManagedPhones,
    WAMessages
  }

  @doc """
  Generate a wa_managed_phone.
  """
  @spec wa_managed_phone_fixture(map()) :: WAManagedPhone.t()
  def wa_managed_phone_fixture(attrs) do
    {:ok, contact} = Contacts.maybe_create_contact(Map.put(attrs, :phone, "917834811231"))

    {:ok, wa_managed_phone} =
      attrs
      |> Enum.into(%{
        is_active: true,
        label: "some label",
        phone: "9829627508",
        phone_id: 242,
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
  Generate a wa_message.
  """
  @spec wa_message_fixture(map()) :: WAGroup.t()
  def wa_message_fixture(attrs) do
    wa_managed_phone = wa_managed_phone_fixture(attrs)

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
end
