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
    do: Fixtures.contact_without_identity_fixture(Map.merge(%{phone: phone()}, attrs))

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

    IdentityBackfill.run(phase: :full, after_id: first.id)

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

    test "reads as the defaults before the backfill and as the copied state after it" do
      contact =
        contact_without_identity(%{
          optin_time: @optin_time,
          optin_status: true,
          bsp_status: :hsm,
          last_message_at: @last_message_at
        })

      assert %{optin_status: false, optin_time: nil, bsp_status: :none, last_message_at: nil} =
               Contacts.get_contact!(contact.id)

      IdentityBackfill.run()

      assert %{
               optin_status: true,
               optin_time: @optin_time,
               bsp_status: :hsm,
               last_message_at: @last_message_at
             } = Contacts.get_contact!(contact.id)
    end

    test "fills a row the application created in the gap, keeping what it wrote" do
      contact =
        contact_without_identity(%{optin_time: @optin_time, optin_status: true, bsp_status: :hsm})

      {:ok, _contact} = Contacts.update_contact(contact, %{bsp_status: :session_and_hsm})

      assert %{bsp_status: :session_and_hsm, optin_status: false} =
               Fixtures.fetch_identity(contact, :whatsapp)

      assert %{updated: updated} = IdentityBackfill.run()
      assert updated >= 1

      assert %{bsp_status: :session_and_hsm, optin_status: true, optin_time: @optin_time} =
               Fixtures.fetch_identity(contact, :whatsapp)
    end

    test "never brings back an opt-in over an opt-out recorded in the gap" do
      contact =
        contact_without_identity(%{optin_time: @optin_time, optin_status: true, bsp_status: :hsm})

      :ok = Contacts.contact_opted_out(contact.phone, contact.organization_id, @last_message_at)

      IdentityBackfill.run()

      assert %{optin_time: nil, optin_status: false, optout_time: @last_message_at} =
               Fixtures.fetch_identity(contact, :whatsapp)
    end

    test "turns a session recorded in the gap into session_and_hsm for an opted in contact" do
      contact =
        contact_without_identity(%{optin_time: @optin_time, optin_status: true, bsp_status: :hsm})

      {:ok, _contact} = Contacts.update_contact(contact, %{bsp_status: :session})

      IdentityBackfill.run()

      assert %{bsp_status: :session_and_hsm} = Fixtures.fetch_identity(contact, :whatsapp)
    end

    test "keeps the later last message time" do
      contact = contact_without_identity(%{last_message_at: @optin_time})
      newer = ~U[2026-10-20 00:00:00Z]

      {:ok, _contact} = Contacts.update_contact(contact, %{last_message_at: newer})

      IdentityBackfill.run()

      assert %{last_message_at: ^newer} = Fixtures.fetch_identity(contact, :whatsapp)
    end

    test "in batches, resumed from the last id, gives every contact its own state" do
      contacts =
        for index <- 1..5,
            do: contact_without_identity(%{optin_status: true, optin_method: "m#{index}"})

      assert %{last_id: last_id} =
               IdentityBackfill.run(
                 phase: :full,
                 batch_size: 2,
                 after_id: List.first(contacts).id
               )

      assert last_id >= List.last(contacts).id
      assert identities(List.first(contacts), :whatsapp) == []

      assert %{inserted: inserted} = IdentityBackfill.run(batch_size: 2)
      assert inserted >= 1
      assert [_one] = identities(List.first(contacts), :whatsapp)

      for {contact, index} <- Enum.with_index(contacts, 1),
          do: assert(Contacts.get_contact!(contact.id).optin_method == "m#{index}")
    end
  end

  describe "the priority pass" do
    @recent ~U[2026-10-20 00:00:00Z]

    defp priority_contacts do
      %{
        opted_out:
          contact_without_identity(%{
            optin_status: false,
            optout_time: ~U[2025-03-04 05:06:07Z],
            optout_method: "user"
          }),
        recent:
          contact_without_identity(%{
            optin_status: true,
            optin_time: ~U[2025-03-04 05:06:07Z],
            last_message_at:
              DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
          }),
        dormant:
          contact_without_identity(%{
            optin_status: true,
            optin_time: ~U[2025-03-04 05:06:07Z],
            last_message_at:
              DateTime.utc_now() |> DateTime.add(-40 * 86_400) |> DateTime.truncate(:second)
          })
      }
    end

    test "copies the opted out and the recently active contacts, and not the others" do
      %{opted_out: opted_out, recent: recent, dormant: dormant} = priority_contacts()

      assert %{phase: :priority, inserted: inserted} = IdentityBackfill.run(phase: :priority)
      assert inserted >= 2

      assert %{optout_method: "user"} = Fixtures.fetch_identity(opted_out, :whatsapp)
      assert %{optin_status: true} = Fixtures.fetch_identity(recent, :whatsapp)
      assert is_nil(Fixtures.fetch_identity(dormant, :whatsapp))

      refute Contacts.get_contact!(dormant.id).optin_status
    end

    test "is followed by the full pass, which leaves the first pass's rows as they are" do
      %{opted_out: opted_out, dormant: dormant} = priority_contacts()

      assert %{phase: :full, inserted: inserted} = IdentityBackfill.run()
      assert inserted >= 1

      assert %{optout_method: "user"} = Fixtures.fetch_identity(opted_out, :whatsapp)
      assert %{optin_status: true} = Fixtures.fetch_identity(dormant, :whatsapp)
      assert %{inserted: 0, updated: 0} = IdentityBackfill.run(phase: :full)
    end

    test "resumes from a contact id within its own pass" do
      %{opted_out: opted_out, recent: recent} = priority_contacts()

      IdentityBackfill.run(phase: :priority, after_id: opted_out.id)

      assert is_nil(Fixtures.fetch_identity(opted_out, :whatsapp))
      assert %{optin_status: true} = Fixtures.fetch_identity(recent, :whatsapp)
    end

    test "an :after_id needs a pass to belong to" do
      assert_raise ArgumentError, fn -> IdentityBackfill.run(after_id: 5) end
    end

    test "never undoes an opt-out the application recorded in the gap" do
      contact =
        contact_without_identity(%{optin_status: true, optin_time: @recent, bsp_status: :hsm})

      :ok = Contacts.contact_opted_out(contact.phone, contact.organization_id, @recent)

      IdentityBackfill.run(phase: :priority)

      assert %{optin_status: false, optout_time: @recent} =
               Fixtures.fetch_identity(contact, :whatsapp)
    end
  end
end
