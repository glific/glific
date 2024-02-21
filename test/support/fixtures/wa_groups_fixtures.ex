defmodule Glific.WAManagedPhonesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.WAGroup` context.
  """
  alias Glific.Contacts
  @doc """
  Generate a wa_managed_phone.
  """
  @spec wa_managed_phone_fixture(map()) :: Glific.WAGroup.WAManagedPhone.t()
  def wa_managed_phone_fixture(attrs \\ %{}) do
    {:ok, contact} = Contacts.maybe_create_contact(Map.put(attrs, :phone , "917834811231"))
    {:ok, wa_managed_phone} =
      attrs
      |> Enum.into(%{
        is_active: true,
        label: "some label",
        phone: "some phone",
        phone_id: 242,
        provider_id: 1,
        contact_id: contact.id
      })
      |> Glific.WAManagedPhones.create_wa_managed_phone()

    wa_managed_phone
  end
end
