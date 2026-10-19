defmodule Glific.Contacts.IdentityBackfillTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.ContactIdentity,
    Contacts.IdentityBackfill,
    Fixtures,
    Repo
  }

  @phone_prefix "9198765"

  defp phone,
    do:
      @phone_prefix <>
        (System.unique_integer([:positive])
         |> Integer.to_string()
         |> String.pad_leading(5, "0")
         |> String.slice(-5, 5))

  defp contact_without_identity(attrs \\ %{}),
    do: Fixtures.pre_identity_contact_fixture(Map.merge(%{phone: phone()}, attrs))

  defp add_identity(contact, channel, identifier) do
    Repo.insert!(
      %ContactIdentity{
        contact_id: contact.id,
        organization_id: contact.organization_id,
        channel: channel,
        identifier: identifier
      },
      skip_organization_id: true
    )
  end

  defp identities(contact, channel),
    do:
      Repo.all(
        from(i in ContactIdentity, where: i.contact_id == ^contact.id and i.channel == ^channel),
        skip_organization_id: true
      )

  test "backfills a contact with a phone, and a rerun adds nothing" do
    contact = contact_without_identity()

    assert %{inserted: inserted} = IdentityBackfill.run(batch_size: 2)
    assert inserted >= 1
    assert [%{identifier: identifier}] = identities(contact, :whatsapp)
    assert identifier == contact.phone

    assert %{inserted: 0} = IdentityBackfill.run()
  end

  test "skips a contact with no phone" do
    {:ok, contact} =
      Contacts.create_contact(%{name: "No phone", organization_id: 1}, :web, "no_phone_user")

    IdentityBackfill.run()

    assert identities(contact, :whatsapp) == []
  end

  test "backfills a contact that also has a web identity, whether or not it has messaged" do
    contact = contact_without_identity(%{last_message_at: nil})
    add_identity(contact, :web, contact.phone)

    IdentityBackfill.run()

    assert [_one] = identities(contact, :whatsapp)
  end

  test "leaves a phone that is already another contact's WhatsApp identity alone" do
    holder = Fixtures.contact_fixture(%{phone: phone()})
    contact = contact_without_identity()

    Repo.delete_all(from(i in ContactIdentity, where: i.contact_id == ^holder.id),
      skip_organization_id: true
    )

    add_identity(holder, :whatsapp, contact.phone)

    IdentityBackfill.run()

    assert [%{contact_id: holder_id}] =
             Repo.all(
               from(i in ContactIdentity,
                 where: i.channel == :whatsapp and i.identifier == ^contact.phone
               ),
               skip_organization_id: true
             )

    assert holder_id == holder.id
    assert identities(contact, :whatsapp) == []
  end

  test "backfills contacts of every organization under their own organization" do
    other_org = Fixtures.organization_fixture(%{name: "Backfill org", shortcode: "bfill"})
    first = contact_without_identity()
    second = contact_without_identity(%{organization_id: other_org.id})

    IdentityBackfill.run()

    assert [%{organization_id: org_1}] = identities(first, :whatsapp)
    assert [%{organization_id: org_2}] = identities(second, :whatsapp)
    assert org_1 == first.organization_id
    assert org_2 == other_org.id
    assert org_1 != org_2
  end

  test "resumes after a given contact id" do
    first = contact_without_identity()
    second = contact_without_identity()

    IdentityBackfill.run(after_id: first.id)

    assert identities(first, :whatsapp) == []
    assert [_one] = identities(second, :whatsapp)
  end

  describe "the WhatsApp state of each contact" do
    @optin_time ~U[2025-03-04 05:06:07Z]
    @last_message_at ~U[2026-10-01 10:11:12Z]

    test "is copied from the contact's own columns onto its new identity" do
      contact =
        contact_without_identity(%{
          optin_time: @optin_time,
          optin_status: true,
          optin_method: "BSP",
          optout_time: nil,
          bsp_status: :session_and_hsm,
          last_message_at: @last_message_at
        })

      IdentityBackfill.run()

      assert [identity] = identities(contact, :whatsapp)

      assert %{
               optin_time: @optin_time,
               optin_status: true,
               optin_method: "BSP",
               optout_time: nil,
               optout_method: nil,
               bsp_status: :session_and_hsm,
               last_message_at: @last_message_at
             } = identity
    end

    test "keeps an opt-out, and never invents an opt-in" do
      contact =
        contact_without_identity(%{
          optin_time: nil,
          optin_status: false,
          optout_time: @optin_time,
          optout_method: "user",
          bsp_status: :none
        })

      IdentityBackfill.run()

      assert [%{optin_time: nil, optin_status: false, optout_time: @optin_time} = identity] =
               identities(contact, :whatsapp)

      assert identity.optout_method == "user"
      assert identity.bsp_status == :none
    end

    test "reads the same through the contact before and after the backfill" do
      contact =
        contact_without_identity(%{
          optin_time: @optin_time,
          optin_status: true,
          bsp_status: :hsm,
          last_message_at: @last_message_at
        })

      before_backfill = Contacts.whatsapp_state(contact)
      IdentityBackfill.run()

      assert Contacts.whatsapp_state(contact) == before_backfill
    end

    test "never overwrites an identity the application already changed" do
      contact =
        contact_without_identity(%{optin_time: @optin_time, optin_status: true, bsp_status: :hsm})

      {:ok, _contact} = Contacts.update_contact(contact, %{bsp_status: :session_and_hsm})

      assert %{bsp_status: :session_and_hsm} = Fixtures.fetch_identity(contact, :whatsapp)

      IdentityBackfill.run()

      assert %{bsp_status: :session_and_hsm, optin_status: true} =
               Fixtures.fetch_identity(contact, :whatsapp)
    end

    test "in batches, resumed from the last id, gives every contact its own state" do
      contacts =
        for index <- 1..5,
            do: contact_without_identity(%{optin_status: true, optin_method: "m#{index}"})

      assert %{last_id: last_id} =
               IdentityBackfill.run(batch_size: 2, after_id: List.first(contacts).id)

      assert last_id >= List.last(contacts).id
      assert identities(List.first(contacts), :whatsapp) == []

      assert %{inserted: inserted} = IdentityBackfill.run(batch_size: 2)
      assert inserted >= 1
      assert [_one] = identities(List.first(contacts), :whatsapp)

      for {contact, index} <- Enum.with_index(contacts, 1),
          do: assert(Contacts.whatsapp_state(contact).optin_method == "m#{index}")
    end
  end
end
