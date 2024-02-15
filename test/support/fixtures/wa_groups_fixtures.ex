defmodule Glific.WAManagedPhonesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.WAGroup` context.
  """

  @doc """
  Generate a wa_managed_phone.
  """
  @spec wa_managed_phone_fixture(map()) :: Glific.WAGroup.WAManagedPhone.t()
  def wa_managed_phone_fixture(attrs \\ %{}) do
    {:ok, wa_managed_phone} =
      attrs
      |> Enum.into(%{
        api_token: "some api_token",
        is_active: true,
        label: "some label",
        phone: "9829627508",
        phone_id: 42_093,
        organization_id: attrs.organization_id,
        provider_id: 1
      })
      |> Glific.WAManagedPhones.create_wa_managed_phone()

    wa_managed_phone
  end
end
