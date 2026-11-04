defmodule Glific.Contacts.TermSearchTest do
  use Glific.DataCase

  alias Glific.{Contacts, Fixtures}

  setup %{organization_id: organization_id} do
    contact =
      Fixtures.contact_fixture(%{
        organization_id: organization_id,
        name: "Meera Kulkarni",
        phone: "910000012345"
      })

    %{contact: contact}
  end

  defp found_ids(organization_id, term) do
    %{filter: %{term: term}, organization_id: organization_id}
    |> Contacts.list_contacts()
    |> Enum.map(& &1.id)
  end

  test "matches a name anywhere in it", %{organization_id: organization_id, contact: contact} do
    assert contact.id in found_ids(organization_id, "kulk")
  end

  test "matches the whole phone number, however it is typed",
       %{organization_id: organization_id, contact: contact} do
    for term <- ["910000012345", "+910000012345", "+91 00000 12345", "+91-0000-012345"],
        do: assert(contact.id in found_ids(organization_id, term), term)
  end

  test "does not match part of a phone number",
       %{organization_id: organization_id, contact: contact} do
    for term <- ["0000012345", "00000", "12345"],
        do: refute(contact.id in found_ids(organization_id, term), term)
  end

  # A phone saved through the API is stored as sent.
  test "matches a stored phone that is not a number exactly as typed, but not part of it",
       %{organization_id: organization_id} do
    coded =
      Fixtures.contact_fixture(%{
        organization_id: organization_id,
        name: "Coded learner",
        phone: "SCH-S49G4048"
      })

    assert coded.id in found_ids(organization_id, "SCH-S49G4048")
    assert coded.id in found_ids(organization_id, " SCH-S49G4048 ")
    refute coded.id in found_ids(organization_id, "S49G")
  end
end
