defmodule Glific.Scripts.RestoreContactWhatsappStateTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
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
      from(c in Contact,
        where: c.id == ^contact.id,
        select: %{
          optin_time: c.legacy_optin_time,
          optin_status: c.legacy_optin_status,
          optin_method: c.legacy_optin_method,
          optout_time: c.legacy_optout_time,
          optout_method: c.legacy_optout_method,
          bsp_status: c.legacy_bsp_status,
          last_message_at: c.legacy_last_message_at
        }
      ),
      skip_organization_id: true
    )
  end

  test "copies the state changes made on the identity back onto the contact" do
    contact =
      Fixtures.pre_identity_contact_fixture(%{
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

    assert columns(contact) == Contacts.whatsapp_state(contact) |> Map.delete(:__struct__)

    assert %{
             optin_time: nil,
             optin_status: false,
             optout_time: @last_message_at,
             optout_method: "flow",
             bsp_status: :none,
             last_message_at: @last_message_at
           } = columns(contact)
  end

  test "leaves a contact with no identity row as it is" do
    contact =
      Fixtures.pre_identity_contact_fixture(%{
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
      from(c in Contact, where: c.id in ^[first.id, second.id]),
      [set: [legacy_optin_method: "stale"]],
      skip_organization_id: true
    )

    assert %{updated: 1} = RestoreContactWhatsappState.run(after_id: first.id)

    assert columns(first).optin_method == "stale"
    assert columns(second).optin_method == "second"
  end
end
