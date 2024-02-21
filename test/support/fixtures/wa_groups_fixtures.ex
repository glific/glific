defmodule Glific.WAManagedPhonesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.WAGroup` context.
  """

  @doc """
  Generate a wa_managed_phone.
  """

  alias Glific.{
    Groups.WAGroup,
    Groups.WhatsappGroup,
    WAGroup.WAManagedPhone,
    WAManagedPhones
  }

  @spec wa_managed_phone_fixture(map()) :: WAManagedPhone.t()
  def wa_managed_phone_fixture(attrs) do
    {:ok, wa_managed_phone} =
      attrs
      |> Enum.into(%{
        is_active: true,
        label: "some label",
        phone: "9829627508",
        phone_id: 42_093,
        organization_id: attrs.organization_id,
        provider_id: 1
      })
      |> WAManagedPhones.create_wa_managed_phone()

    wa_managed_phone
  end

  @doc """
  Generate a wa_managed_phone.
  """
  @spec wa_group_fixture(map()) :: WAGroup.t()
  def wa_group_fixture(attrs) do
    {:ok, wa_group} =
      attrs
      |> Enum.into(%{
        label: "some label",
        bsp_id: "120363238104@g.us",
        wa_managed_phone: "9829627508",
        wa_managed_phone_id: attrs.wa_managed_phone_id,
        organization_id: attrs.organization_id
      })
      |> WhatsappGroup.create_wa_group()

    wa_group
  end
end
