defmodule Glific.Contacts.IdentityStateBackfillTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.ContactIdentity,
    Contacts.IdentityStateBackfill,
    Contacts.IdentityStateWorker,
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

  defp set_identity!(contact, changes) do
    Repo.update_all(
      from(i in ContactIdentity, where: i.contact_id == ^contact.id and i.channel == :whatsapp),
      set: changes
    )
  end

  defp copy_from(contact), do: IdentityStateBackfill.copy_chunk(contact.id - 1, 1_000_000)

  describe "copy_chunk/2" do
    test "creates the identity of a contact with the contact's state" do
      contact = contact_with_state()

      assert %{inserted: inserted, last_id: last_id} = copy_from(contact)
      assert inserted >= 1
      assert last_id >= contact.id

      assert [%{identifier: identifier, channel: :whatsapp}] = identities(contact)
      assert identifier == contact.phone
      assert %{contact: state, identity: state} = Fixtures.whatsapp_optin_fields(contact)
      assert %{optin_status: true, bsp_status: :session_and_hsm} = state
    end

    test "stores a nil optin_status as false" do
      contact = contact_with_state()

      Repo.update_all(from(c in "contacts", where: c.id == ^contact.id),
        set: [optin_status: nil]
      )

      copy_from(contact)

      assert [%{optin_status: false}] = identities(contact)
    end

    test "overwrites a stale identity of the same contact and leaves one that matches" do
      contact = contact_with_state()
      copy_from(contact)
      set_identity!(contact, optin_status: false, optout_time: @optin_time)

      assert %{updated: 1, inserted: 0} = copy_from(contact)

      assert %{contact: state, identity: state} = Fixtures.whatsapp_optin_fields(contact)
      assert state.optin_status
      assert %{updated: 0, inserted: 0} = copy_from(contact)
    end

    test "overwrites an identity row that existed with default state" do
      contact = Fixtures.contact_fixture()
      set_identity!(contact, optin_status: false, optin_time: nil, bsp_status: :none)

      Repo.update_all(from(c in "contacts", where: c.id == ^contact.id),
        set: [optin_status: true, optin_time: @optin_time, bsp_status: "hsm"]
      )

      assert %{updated: 1, inserted: 0} = copy_from(contact)

      assert %{contact: state, identity: state} = Fixtures.whatsapp_optin_fields(contact)
      assert %{optin_status: true, optin_time: @optin_time, bsp_status: :hsm} = state
    end

    test "skips a contact with no phone and does not touch a web identity" do
      {:ok, contact} =
        Contacts.create_contact(%{name: "No phone", organization_id: 1}, :web, "no_phone_user")

      Repo.update_all(from(c in "contacts", where: c.id == ^contact.id),
        set: [optin_status: true]
      )

      copy_from(contact)

      assert [%{channel: :web, optin_status: false}] = identities(contact)
    end

    test "leaves a phone that is another contact's WhatsApp identity alone" do
      holder = Fixtures.contact_fixture()
      contact = contact_with_state()

      Repo.update_all(from(i in ContactIdentity, where: i.contact_id == ^holder.id),
        set: [identifier: contact.phone, optin_status: false, bsp_status: :none]
      )

      copy_from(contact)

      assert [%{contact_id: holder_id, optin_status: false}] =
               Repo.all(
                 from(i in ContactIdentity,
                   where: i.channel == :whatsapp and i.identifier == ^contact.phone
                 ),
                 skip_organization_id: true
               )

      assert holder_id == holder.id
      assert identities(contact) == []

      assert %{mismatched: 1, sample_ids: [mismatched_id]} =
               IdentityStateBackfill.find_mismatches(after_id: contact.id - 1)

      assert mismatched_id == contact.id
    end

    test "creates identities under each contact's own organization" do
      other_organization =
        Fixtures.organization_fixture(%{name: "Backfill org", shortcode: "bfill"})

      first = contact_with_state()
      second = contact_with_state(%{organization_id: other_organization.id})

      copy_from(first)

      assert [%{organization_id: first_organization_id}] = identities(first)
      assert [%{organization_id: second_organization_id}] = identities(second)
      assert first_organization_id == first.organization_id
      assert second_organization_id == other_organization.id
    end

    test "continues after a given contact id and bounds a chunk by batch size" do
      first = contact_with_state()
      second = contact_with_state()
      third = contact_with_state()

      assert %{scanned: 1, last_id: last_id} = IdentityStateBackfill.copy_chunk(first.id, 1)
      assert last_id == second.id
      assert identities(first) == []
      assert [_identity] = identities(second)
      assert identities(third) == []
    end
  end

  describe "the chain" do
    test "start/1 refuses a second chain while one is queued" do
      assert {:ok, %Oban.Job{}} = IdentityStateBackfill.start()
      assert {:error, :already_running} = IdentityStateBackfill.start()
      assert [%{state: "available", after_id: 0}] = IdentityStateBackfill.status()
    end

    test "start/1 passes its options as job args" do
      assert {:ok, _job} = IdentityStateBackfill.start(after_id: 5, batch_size: 7, pause: 0)

      assert_enqueued(
        worker: IdentityStateWorker,
        args: %{after_id: 5, batch_size: 7, pause: 0},
        prefix: "global"
      )
    end

    test "a full chunk enqueues the next with the last id, a short one ends the chain" do
      first = contact_with_state()
      second = contact_with_state()
      third = contact_with_state()
      args = %{"after_id" => first.id - 1, "batch_size" => 2, "pause" => 0}

      assert :ok = perform_job(IdentityStateWorker, args)
      assert [_identity] = identities(first)
      assert [_identity] = identities(second)
      assert identities(third) == []

      assert_enqueued(
        worker: IdentityStateWorker,
        args: %{after_id: second.id, batch_size: 2},
        prefix: "global"
      )

      assert :ok = perform_job(IdentityStateWorker, %{args | "after_id" => second.id})
      assert [_identity] = identities(third)
      refute_enqueued(worker: IdentityStateWorker, args: %{after_id: third.id}, prefix: "global")
    end

    test "drains the whole chain with no contact skipped or done twice" do
      contacts = for _ <- 1..5, do: contact_with_state()
      first_id = hd(contacts).id

      assert {:ok, _job} =
               IdentityStateBackfill.start(after_id: first_id - 1, batch_size: 2, pause: 0)

      assert %{success: success} =
               Oban.drain_queue(queue: :purge, with_scheduled: true, with_recursion: true)

      assert success >= 3
      assert Enum.all?(contacts, &(length(identities(&1)) == 1))
      assert IdentityStateBackfill.status() == []
      assert %{mismatched: 0} = IdentityStateBackfill.find_mismatches(after_id: first_id - 1)
    end

    test "a rerun changes nothing and a resume skips what is before after_id" do
      first = contact_with_state()
      second = contact_with_state()

      assert :ok =
               perform_job(IdentityStateWorker, %{
                 "after_id" => first.id,
                 "batch_size" => 100,
                 "pause" => 0
               })

      assert identities(first) == []
      assert [_identity] = identities(second)

      assert :ok =
               perform_job(IdentityStateWorker, %{
                 "after_id" => first.id - 1,
                 "batch_size" => 100,
                 "pause" => 0
               })

      assert [_identity] = identities(first)
      assert %{updated: 0, inserted: 0} = copy_from(first)
    end

    test "stop/0 cancels the queued link and a cancelled running link does not chain" do
      assert {:ok, job} = IdentityStateBackfill.start(batch_size: 1, pause: 0)
      contact_with_state()
      contact_with_state()

      assert {:ok, 1} = IdentityStateBackfill.stop()
      assert IdentityStateBackfill.status() == []

      assert :ok =
               IdentityStateWorker.perform(%{
                 Repo.reload!(job, prefix: "global")
                 | args: job.args
               })

      refute_enqueued(worker: IdentityStateWorker, state: "available", prefix: "global")
    end
  end

  describe "find_mismatches/1 and fix_mismatches/1" do
    test "report a contact changed after the copy, and change nothing" do
      contact = contact_with_state()
      copy_from(contact)

      Repo.update_all(from(c in "contacts", where: c.id == ^contact.id),
        set: [optin_status: false, optout_time: @optin_time]
      )

      missing = contact_with_state()
      in_step = contact_with_state()
      set_identity!(in_step, optin_status: true)

      assert %{mismatched: mismatched, sample_ids: sample_ids} =
               IdentityStateBackfill.find_mismatches(after_id: contact.id - 1, batch_size: 2)

      assert mismatched >= 2
      assert contact.id in sample_ids
      assert missing.id in sample_ids
      assert identities(missing) == []
    end

    test "fix_mismatches/1 repairs them, so a second check finds none" do
      missing = contact_with_state()
      differing = contact_with_state()
      copy_from(missing)
      set_identity!(differing, optin_status: false, last_message_at: nil)
      later = contact_with_state()

      assert %{fixed: fixed} = IdentityStateBackfill.fix_mismatches(after_id: missing.id - 1)
      assert fixed >= 2

      assert %{contact: state, identity: state} = Fixtures.whatsapp_optin_fields(differing)
      assert %{contact: state, identity: state} = Fixtures.whatsapp_optin_fields(later)

      assert %{mismatched: 0, sample_ids: []} =
               IdentityStateBackfill.find_mismatches(after_id: missing.id - 1)
    end

    test "can be limited to one organization" do
      other_organization =
        Fixtures.organization_fixture(%{name: "Mismatch org", shortcode: "mismatch"})

      mine = contact_with_state()
      theirs = contact_with_state(%{organization_id: other_organization.id})

      assert %{sample_ids: sample_ids} =
               IdentityStateBackfill.find_mismatches(
                 after_id: mine.id - 1,
                 organization_id: other_organization.id
               )

      assert theirs.id in sample_ids
      refute mine.id in sample_ids
    end

    test "do not count a contact with no phone" do
      {:ok, contact} =
        Contacts.create_contact(
          %{name: "No phone", organization_id: 1},
          :web,
          "mismatch_no_phone"
        )

      assert %{sample_ids: sample_ids} =
               IdentityStateBackfill.find_mismatches(after_id: contact.id - 1)

      refute contact.id in sample_ids
    end
  end
end
