defmodule Glific.WAGroupsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.WAGroup` context.
  """

  @doc """
  Generate a wa_managed_phone.
  """
  def wa_managed_phone_fixture(attrs \\ %{}) do
    {:ok, wa_managed_phone} =
      attrs
      |> Enum.into(%{
        api_token: "some api_token",
        is_active: true,
        label: "some label",
        phone: "some phone",
        phone_id: "some random string identifier",
        product_id: "another random string identifier",
        organization_id: 1,
        provider_id: 1
      })
      |> Glific.WAGroups.create_wa_managed_phone()

    wa_managed_phone
  end
end
