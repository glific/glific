defmodule Glific.WAManagedPhonesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.WAGroup` context.
  """

  @doc """
  Generate a wa_managed_phone.
  """
  @spec wa_managed_phone_fixture(map()) :: Glific.WAGroup.WAManagedPhone.t()
  def wa_managed_phone_fixture(attrs) do
    {:ok, wa_managed_phone} =
      params
      |> Map.merge(attrs)
      |> Glific.WAManagedPhones.create_wa_managed_phone()

    wa_managed_phone
  end
end
