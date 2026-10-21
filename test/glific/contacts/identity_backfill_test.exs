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

  @optin_time ~U[2025-03-04 05:06:07Z]
  @last_message_at ~U[2026-10-01 10:11:12Z]

  defp contact_with_state(attrs \\ %{}) do
    Fixtures.contact_without_identity_fixture(
      Map.merge(
        %{
          optin_time: @optin_time,
          optin_status: true,
          optin_method: "BSP",
          bsp_status: :session_and_hsm,
          last_message_at: @last_message_at
        },
        attrs
      )
    )
  end

  defp identities(contact) do
    Repo.all(from(i in ContactIdentity, where: i.contact_id == ^contact.id),
      skip_organization_id: true
    )
  end

  defp mismatch!(contact, changes) do
    Repo.update_all(
      from(i in ContactIdentity, where: i.contact_id == ^contact.id and i.channel == :whatsapp),
      set: changes
    )
  end

  describe "run/1" do
    test "creates the identity of a contact with the contact's state" do
      contact = contact_with_state()

      assert %{inserted: inserted, last_id: last_id} = IdentityBackfill.run(batch_size: 2)
      assert inserted >= 1
      assert last_id >= contact.id

      assert [%{identifier: identifier, channel: :whatsapp}] = identities(contact)
      assert identifier == contact.phone
      assert %{contact: state, identity: state} = Fixtures.whatsapp_state(contact)
      assert %{optin_status: true, bsp_status: :session_and_hsm} = state
    end

    test "overwrites an identity that differs and leaves one that matches" do
      contact = contact_with_state()
      IdentityBackfill.run()
      mismatch!(contact, optin_status: false, optout_time: @optin_time)

      assert %{updated: 1, inserted: 0} = IdentityBackfill.run()

      assert %{contact: state, identity: state} = Fixtures.whatsapp_state(contact)
      assert state.optin_status
      assert %{updated: 0, inserted: 0} = IdentityBackfill.run()
    end

    test "overwrites an identity row that existed before the backfill with the contact's state" do
      contact = Fixtures.contact_fixture()
      IdentityBackfill.run()
      mismatch!(contact, optin_status: false, optin_time: nil, bsp_status: :none)

      Repo.update_all(from(c in "contacts", where: c.id == ^contact.id),
        set: [optin_status: true, optin_time: @optin_time, bsp_status: "hsm"]
      )

      assert %{updated: 1, inserted: 0} = IdentityBackfill.run()

      assert %{contact: state, identity: state} = Fixtures.whatsapp_state(contact)
      assert %{optin_status: true, optin_time: @optin_time, bsp_status: :hsm} = state
    end

    test "skips a contact with no phone" do
      {:ok, contact} =
        Contacts.create_contact(%{name: "No phone", organization_id: 1}, :web, "no_phone_user")

      Repo.update_all(from(c in "contacts", where: c.id == ^contact.id),
        set: [optin_status: true]
      )

      IdentityBackfill.run()

      assert [%{channel: :web}] = identities(contact)
    end

    test "leaves a phone that is another contact's WhatsApp identity alone" do
      holder = Fixtures.contact_fixture()
      contact = contact_with_state()

      Repo.update_all(
        from(i in ContactIdentity, where: i.contact_id == ^holder.id),
        set: [identifier: contact.phone]
      )

      IdentityBackfill.run()

      assert [%{contact_id: holder_id}] =
               Repo.all(
                 from(i in ContactIdentity,
                   where: i.channel == :whatsapp and i.identifier == ^contact.phone
                 ),
                 skip_organization_id: true
               )

      assert holder_id == holder.id
      assert identities(contact) == []
    end

    test "creates identities under each contact's own organization" do
      other_organization =
        Fixtures.organization_fixture(%{name: "Backfill org", shortcode: "bfill"})

      first = contact_with_state()
      second = contact_with_state(%{organization_id: other_organization.id})

      IdentityBackfill.run()

      assert [%{organization_id: first_organization_id}] = identities(first)
      assert [%{organization_id: second_organization_id}] = identities(second)
      assert first_organization_id == first.organization_id
      assert second_organization_id == other_organization.id
    end

    test "resumes after a given contact id" do
      first = contact_with_state()
      second = contact_with_state()

      IdentityBackfill.run(after_id: first.id)

      assert identities(first) == []
      assert [_identity] = identities(second)
    end
  end

  describe "find_mismatches/1 and fix_mismatches/1" do
    test "reports contacts whose identity is missing or differs, and changes nothing" do
      missing = contact_with_state()
      differing = Fixtures.contact_fixture()
      mismatch!(differing, bsp_status: :none)
      in_step = Fixtures.contact_fixture()

      assert %{mismatched: mismatched, sample_ids: sample_ids} =
               IdentityBackfill.find_mismatches(after_id: missing.id - 1, batch_size: 2)

      assert mismatched >= 2
      assert missing.id in sample_ids
      assert differing.id in sample_ids
      refute in_step.id in sample_ids
      assert identities(missing) == []
    end

    test "fix_mismatches/1 copies the mismatched contacts, so a second check finds none" do
      missing = contact_with_state()
      differing = Fixtures.contact_fixture()
      mismatch!(differing, optin_status: true, last_message_at: @last_message_at)

      assert %{fixed: fixed} = IdentityBackfill.fix_mismatches(after_id: missing.id - 1)
      assert fixed >= 2

      assert %{contact: state, identity: state} = Fixtures.whatsapp_state(missing)
      assert %{contact: state, identity: state} = Fixtures.whatsapp_state(differing)

      assert %{mismatched: 0, sample_ids: []} =
               IdentityBackfill.find_mismatches(after_id: missing.id - 1)
    end

    test "can be limited to one organization" do
      other_organization =
        Fixtures.organization_fixture(%{name: "Mismatch org", shortcode: "mismatch"})

      mine = contact_with_state()
      theirs = contact_with_state(%{organization_id: other_organization.id})

      assert %{sample_ids: sample_ids} =
               IdentityBackfill.find_mismatches(
                 after_id: mine.id - 1,
                 organization_id: other_organization.id
               )

      assert theirs.id in sample_ids
      refute mine.id in sample_ids
    end

    test "does not count a contact with no phone" do
      {:ok, contact} =
        Contacts.create_contact(
          %{name: "No phone", organization_id: 1},
          :web,
          "mismatch_no_phone"
        )

      assert %{sample_ids: sample_ids} =
               IdentityBackfill.find_mismatches(after_id: contact.id - 1)

      refute contact.id in sample_ids
    end
  end
end
