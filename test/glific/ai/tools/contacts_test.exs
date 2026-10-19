defmodule Glific.AI.Tools.ContactsTest do
  use Glific.DataCase

  alias Glific.{
    AI.Tools.Contacts,
    Fixtures
  }

  @optin_time ~U[2025-03-04 05:06:07Z]

  test "get_contact reports the WhatsApp state of a contact from its identity" do
    contact =
      Fixtures.contact_fixture(%{
        optin_time: @optin_time,
        optin_status: true,
        bsp_status: :session_and_hsm,
        last_message_at: ~U[2026-10-01 10:11:12Z]
      })

    assert {:ok, described} =
             Contacts.run("get_contact", %{contact_id: contact.id, include: [], limit: 5})

    assert %{
             bsp_status: :session_and_hsm,
             optin_status: true,
             optin_time: @optin_time,
             optout_time: nil,
             last_message_at: ~U[2026-10-01 10:11:12Z]
           } = described
  end

  test "get_contact reports the state of a contact that has no identity yet from its columns" do
    contact =
      Fixtures.pre_identity_contact_fixture(%{
        optin_time: @optin_time,
        optin_status: true,
        bsp_status: :hsm
      })

    assert {:ok, %{bsp_status: :hsm, optin_status: true, optin_time: @optin_time}} =
             Contacts.run("get_contact", %{contact_id: contact.id, include: [], limit: 5})
  end

  test "list_contacts reports the state of every contact it returns" do
    with_identity = Fixtures.contact_fixture(%{name: "Ai Tool Identity", bsp_status: :session})

    without_identity =
      Fixtures.pre_identity_contact_fixture(%{name: "Ai Tool Columns", bsp_status: :hsm})

    assert {:ok, contacts} = Contacts.run("list_contacts", %{term: "Ai Tool", limit: 10})

    assert %{bsp_status: :session} = Enum.find(contacts, &(&1.id == with_identity.id))
    assert %{bsp_status: :hsm} = Enum.find(contacts, &(&1.id == without_identity.id))
  end
end
