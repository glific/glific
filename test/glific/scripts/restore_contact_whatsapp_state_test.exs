defmodule Glific.Scripts.RestoreContactWhatsappStateTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Fixtures,
    Repo,
    Scripts.RestoreContactWhatsappState
  }

  @optin_time ~U[2025-03-04 05:06:07Z]
  @last_message_at ~U[2026-10-01 10:11:12Z]

  defp phone,
    do:
      "9198762" <>
        (System.unique_integer([:positive])
         |> Integer.to_string()
         |> String.pad_leading(5, "0")
         |> String.slice(-5, 5))

  defp columns(contact) do
    Repo.one!(
      from(c in "contacts",
        where: c.id == ^contact.id,
        select: %{
          optin_time: type(c.optin_time, :utc_datetime),
          optin_status: c.optin_status,
          optin_method: c.optin_method,
          optout_time: type(c.optout_time, :utc_datetime),
          optout_method: c.optout_method,
          bsp_status: type(c.bsp_status, Glific.Enums.ContactProviderStatus),
          last_message_at: type(c.last_message_at, :utc_datetime)
        }
      ),
      skip_organization_id: true
    )
  end

  test "copies the state changes made on the identity back onto the contact" do
    contact =
      Fixtures.contact_without_identity_fixture(%{
        phone: phone(),
        optin_time: @optin_time,
        optin_status: true,
        optin_method: "BSP",
        bsp_status: :hsm
      })

    {:ok, _contact} =
      Contacts.update_contact(contact, %{
        bsp_status: :session_and_hsm,
        last_message_at: @last_message_at
      })

    :ok = Contacts.contact_opted_out(contact.phone, 1, @last_message_at, "flow")

    assert %{optin_status: true, bsp_status: :hsm} = columns(contact)

    assert %{updated: updated, last_id: last_id} = RestoreContactWhatsappState.run()
    assert updated >= 1
    assert last_id >= contact.id

    restored = columns(contact)
    assert restored == Map.take(Contacts.get_contact!(contact.id), Map.keys(restored))

    assert %{
             optin_time: nil,
             optin_status: false,
             optout_time: @last_message_at,
             optout_method: "flow",
             bsp_status: :none,
             last_message_at: @last_message_at
           } = columns(contact)
  end

  test "does not overwrite a recorded opt-in with the defaults of a row created without consent" do
    contact =
      Fixtures.contact_without_identity_fixture(%{
        phone: phone(),
        optin_time: @optin_time,
        optin_status: true,
        optin_method: "BSP",
        bsp_status: :hsm
      })

    {:ok, _contact} = Contacts.update_contact(contact, %{last_message_at: @last_message_at})

    assert %{optin_status: false, optin_time: nil} = Fixtures.fetch_identity(contact, :whatsapp)

    RestoreContactWhatsappState.run()

    assert %{
             optin_time: @optin_time,
             optin_status: true,
             optin_method: "BSP",
             bsp_status: :hsm,
             last_message_at: @last_message_at
           } = columns(contact)
  end

  test "adds a session from a row created without consent to the contact's own status" do
    contact = Fixtures.contact_without_identity_fixture(%{phone: phone(), bsp_status: :hsm})

    {:ok, _contact} = Contacts.update_contact(contact, %{bsp_status: :session})
    RestoreContactWhatsappState.run()

    assert %{bsp_status: :session_and_hsm, optin_status: false} = columns(contact)
  end

  test "copies a recorded opt-in back onto the contact" do
    contact = Fixtures.contact_without_identity_fixture(%{phone: phone()})

    {:ok, _contact} = Contacts.contact_opted_in(%{phone: contact.phone}, 1, @optin_time)

    assert %{optin_status: false, optin_time: nil} = columns(contact)

    RestoreContactWhatsappState.run()

    assert %{optin_status: true, optin_time: @optin_time, optin_method: "BSP", bsp_status: :hsm} =
             columns(contact)
  end

  test "leaves a contact with no identity row as it is" do
    contact =
      Fixtures.contact_without_identity_fixture(%{
        phone: phone(),
        optin_time: @optin_time,
        optin_status: true,
        bsp_status: :hsm
      })

    before = columns(contact)
    RestoreContactWhatsappState.run()

    assert columns(contact) == before
  end

  test "is idempotent, and resumes from a given contact id" do
    first = Fixtures.contact_fixture(%{phone: phone(), optin_method: "first"})
    second = Fixtures.contact_fixture(%{phone: phone(), optin_method: "second"})

    assert %{updated: updated} = RestoreContactWhatsappState.run(batch_size: 3)
    assert updated >= 2
    assert %{updated: 0} = RestoreContactWhatsappState.run()

    Repo.update_all(
      from(c in "contacts", where: c.id in ^[first.id, second.id]),
      [set: [optin_method: "stale"]],
      skip_organization_id: true
    )

    assert %{updated: 1} = RestoreContactWhatsappState.run(after_id: first.id)

    assert columns(first).optin_method == "stale"
    assert columns(second).optin_method == "second"
  end
end
