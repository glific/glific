defmodule Glific.Contacts.WhatsAppStateTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactHistory,
    Fixtures,
    Partners,
    Repo
  }

  @optin_time ~U[2025-03-04 05:06:07Z]
  @last_message_at ~U[2026-10-01 10:11:12Z]

  @legacy_state %{
    optin_time: @optin_time,
    optin_status: true,
    optin_method: "BSP",
    optout_time: nil,
    optout_method: "earlier",
    bsp_status: :hsm,
    last_message_at: @last_message_at
  }

  defp phone,
    do:
      "9198760" <>
        (System.unique_integer([:positive])
         |> Integer.to_string()
         |> String.pad_leading(5, "0")
         |> String.slice(-5, 5))

  defp legacy_columns(contact) do
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
      )
    )
  end

  defp pre_identity_contact(state \\ @legacy_state),
    do: Fixtures.pre_identity_contact_fixture(Map.put(state, :phone, phone()))

  describe "whatsapp_state/1" do
    test "reads the WhatsApp identity of a contact" do
      contact =
        Fixtures.contact_fixture(%{
          phone: phone(),
          optin_time: @optin_time,
          optin_status: true,
          optin_method: "BSP",
          bsp_status: :session_and_hsm,
          last_message_at: @last_message_at
        })

      assert %{
               optin_time: @optin_time,
               optin_status: true,
               optin_method: "BSP",
               optout_time: nil,
               bsp_status: :session_and_hsm,
               last_message_at: @last_message_at
             } = Contacts.whatsapp_state(contact)

      assert Fixtures.fetch_identity(contact, :whatsapp).optin_method == "BSP"
    end

    test "falls back to the contact's own columns while it has no identity" do
      contact = pre_identity_contact()

      assert is_nil(Fixtures.fetch_identity(contact, :whatsapp))
      assert Contacts.whatsapp_state(contact) == @legacy_state
    end

    test "treats a contact with no phone as never opted in" do
      contact = Fixtures.contact_without_phone_fixture()

      assert %{optin_time: nil, optin_status: false, bsp_status: :none, last_message_at: nil} =
               Contacts.whatsapp_state(contact)
    end

    test "never takes a field from the contact once the identity exists, even a null one" do
      contact = pre_identity_contact()

      :ok = Contacts.contact_opted_out(contact.phone, contact.organization_id, DateTime.utc_now())

      state = Contacts.whatsapp_state(contact)
      assert is_nil(state.optin_time)
      assert state.optin_status == false
      assert state.optout_time != nil
      assert state.bsp_status == :none
    end

    test "whatsapp_states/1 answers for identities and pre-identity contacts alike" do
      with_identity = Fixtures.contact_fixture(%{phone: phone(), optin_method: "BSP"})
      without_identity = pre_identity_contact()

      states = Contacts.whatsapp_states([with_identity, without_identity])

      assert states[with_identity.id].optin_method == "BSP"
      assert states[without_identity.id] == @legacy_state
      assert Contacts.whatsapp_states([]) == %{}
    end
  end

  describe "writes go to the WhatsApp identity" do
    test "update_contact/2 changes the identity and leaves the contact's own columns alone" do
      contact = Fixtures.contact_fixture(%{phone: phone()})
      before = legacy_columns(contact)

      {:ok, _contact} =
        Contacts.update_contact(contact, %{
          optin_status: false,
          optin_time: nil,
          optout_time: @optin_time,
          optout_method: "user",
          bsp_status: :none,
          last_message_at: @last_message_at
        })

      assert %{
               optin_status: false,
               optin_time: nil,
               optout_time: @optin_time,
               optout_method: "user",
               bsp_status: :none,
               last_message_at: @last_message_at
             } = Contacts.whatsapp_state(contact)

      assert legacy_columns(contact) == before
    end

    test "a write to a contact with no identity creates it from the contact, then applies the change" do
      contact = pre_identity_contact()

      {:ok, _contact} = Contacts.update_contact(contact, %{bsp_status: :session_and_hsm})

      assert %{
               optin_time: @optin_time,
               optin_method: "BSP",
               optout_method: "earlier",
               last_message_at: @last_message_at,
               bsp_status: :session_and_hsm
             } = Fixtures.fetch_identity(contact, :whatsapp)

      assert legacy_columns(contact).bsp_status == :hsm
    end

    test "a write marks the contact updated, so the next BigQuery sync picks it up" do
      contact = Fixtures.contact_fixture(%{phone: phone()})
      old = DateTime.add(contact.updated_at, -3600)
      Repo.update_all(from(c in Contact, where: c.id == ^contact.id), set: [updated_at: old])

      {:ok, _contact} = Contacts.update_contact(contact, %{bsp_status: :hsm})

      assert DateTime.compare(Repo.get!(Contact, contact.id).updated_at, old) == :gt
    end

    test "update_contact/2 on a contact with no phone changes nothing on WhatsApp" do
      contact = Fixtures.contact_without_phone_fixture()

      assert {:ok, _contact} = Contacts.update_contact(contact, %{bsp_status: :session})
      assert Contacts.whatsapp_state(contact).bsp_status == :none
    end

    test "create_contact/1 stores the state on the new identity" do
      {:ok, contact} =
        Contacts.create_contact(%{
          phone: phone(),
          organization_id: 1,
          optin_time: @optin_time,
          optin_status: true,
          optin_method: "Import",
          bsp_status: :hsm
        })

      assert %{optin_time: @optin_time, optin_method: "Import", bsp_status: :hsm} =
               Fixtures.fetch_identity(contact, :whatsapp)

      assert legacy_columns(contact).optin_time == nil
      assert legacy_columns(contact).bsp_status == :none
    end

    test "upsert/1 keeps an existing contact's state and applies the given one" do
      contact = pre_identity_contact()

      {:ok, upserted} =
        Contacts.upsert(%{
          phone: contact.phone,
          organization_id: 1,
          name: "renamed",
          bsp_status: :session_and_hsm
        })

      assert upserted.id == contact.id

      assert %{optin_time: @optin_time, optout_method: "earlier", bsp_status: :session_and_hsm} =
               Contacts.whatsapp_state(contact)
    end

    test "insert_contacts/2 seeds existing contacts and applies the entry's state" do
      contact = pre_identity_contact()
      new_phone = phone()

      Contacts.insert_contacts(
        [
          %{
            phone: contact.phone,
            name: "imported",
            language_id: 1,
            organization_id: 1,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now(),
            optin_method: "Import",
            bsp_status: :session_and_hsm
          },
          %{
            phone: new_phone,
            name: "brand new",
            language_id: 1,
            organization_id: 1,
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        ],
        organization_id: 1,
        on_conflict: {:replace, [:name]},
        conflict_target: [:phone, :organization_id]
      )

      assert %{
               optin_method: "Import",
               bsp_status: :session_and_hsm,
               last_message_at: @last_message_at
             } =
               Contacts.whatsapp_state(contact)

      {:ok, created} = Contacts.fetch_by_identity(:whatsapp, new_phone)

      assert %{optin_status: false, bsp_status: :none} =
               Fixtures.fetch_identity(created, :whatsapp)
    end

    test "a new phone keeps the state the contact had on WhatsApp" do
      contact =
        Fixtures.contact_fixture(%{phone: phone(), optin_method: "BSP", optin_status: true})

      new_phone = phone()

      {:ok, moved} = Contacts.update_phone(contact, new_phone)

      identity = Fixtures.fetch_identity(moved, :whatsapp)
      assert identity.identifier == new_phone
      assert identity.optin_method == "BSP"
      assert identity.optin_status
    end

    test "a new phone on a pre-identity contact carries the contact's own state" do
      contact = pre_identity_contact()
      new_phone = phone()

      {:ok, moved} = Contacts.update_phone(contact, new_phone)

      assert Contacts.whatsapp_state(moved) == @legacy_state
      assert Fixtures.fetch_identity(moved, :whatsapp).identifier == new_phone
    end
  end

  describe "update_contact/2" do
    test "writes nothing, on the contact or its identity, when the contact change is invalid" do
      contact = Fixtures.contact_fixture(%{phone: phone(), bsp_status: :hsm})

      assert {:error, %Ecto.Changeset{}} =
               Contacts.update_contact(contact, %{phone: nil, bsp_status: :session})

      assert Contacts.whatsapp_state(contact).bsp_status == :hsm
    end

    test "on a contact with no phone succeeds without touching WhatsApp state" do
      contact = Fixtures.contact_without_phone_fixture()

      assert {:ok, _} = Contacts.update_contact(contact, %{name: "renamed", optin_status: true})
      assert Contacts.whatsapp_state(contact).optin_status == false
    end
  end

  describe "identity rows that exist before the state columns" do
    test "carry their contact's state once the migration has copied it" do
      contact = pre_identity_contact(%{@legacy_state | optin_status: true})

      Repo.insert!(
        %Glific.Contacts.ContactIdentity{
          contact_id: contact.id,
          organization_id: contact.organization_id,
          channel: :whatsapp,
          identifier: contact.phone
        },
        skip_organization_id: true
      )

      assert %{optin_time: nil, bsp_status: :none} = Contacts.whatsapp_state(contact)
      assert {:error, _} = Contacts.can_send_message_to?(contact, true)

      [migration_file] =
        Path.wildcard(
          "priv/repo/migrations/20261019100000_add_whatsapp_state_to_contact_identities.exs"
        )

      [{migration, _}] = Code.compile_file(migration_file)
      Repo.query!(migration.copy_state_sql(), [], skip_organization_id: true)

      assert Contacts.whatsapp_state(contact) == @legacy_state
      assert {:ok, nil} = Contacts.can_send_message_to?(contact, true)
    end
  end

  describe "opt-in and opt-out" do
    test "contact_opted_in/4 opts a pre-identity contact in on its identity" do
      contact = pre_identity_contact(%{optin_status: false, bsp_status: :none})
      time = ~U[2026-10-10 10:00:00Z]

      assert {:ok, _contact} =
               Contacts.contact_opted_in(%{phone: contact.phone}, 1, time,
                 method: "WA",
                 message_id: "wamid.1"
               )

      assert %{optin_time: ^time, optin_status: true, optin_method: "WA", optout_time: nil} =
               Fixtures.fetch_identity(contact, :whatsapp)

      assert legacy_columns(contact).optin_status == false

      assert [history] =
               Repo.all(
                 from(h in ContactHistory,
                   where: h.contact_id == ^contact.id and h.event_type == "contact_opted_in"
                 )
               )

      assert history.event_meta["optin_message_id"] == "wamid.1"
    end

    test "contact_opted_in/4 from the BSP is ignored for a contact already opted in on its identity" do
      contact =
        Fixtures.contact_fixture(%{phone: phone(), optin_status: true, optin_method: "WA"})

      assert {:ok, _contact} =
               Contacts.contact_opted_in(%{phone: contact.phone}, 1, DateTime.utc_now(),
                 method: "BSP"
               )

      assert Contacts.whatsapp_state(contact).optin_method == "WA"
    end

    test "contact_opted_in/4 for an unknown phone creates the contact with its opt-in" do
      new_phone = phone()

      assert {:ok, contact} =
               Contacts.contact_opted_in(%{phone: new_phone}, 1, DateTime.utc_now(),
                 method: "BSP"
               )

      assert %{optin_status: true, optin_method: "BSP", bsp_status: bsp_status} =
               Fixtures.fetch_identity(contact, :whatsapp)

      assert bsp_status in [:hsm, :session_and_hsm]
    end

    test "contact_opted_out/4 records the opt-out on the identity of a pre-identity contact" do
      contact = pre_identity_contact()

      assert :ok = Contacts.contact_opted_out(contact.phone, 1, @last_message_at, "flow")

      assert %{
               optout_time: @last_message_at,
               optout_method: "flow",
               optin_time: nil,
               optin_status: false,
               optin_method: nil,
               bsp_status: :none
             } = Fixtures.fetch_identity(contact, :whatsapp)

      assert Repo.get!(Contact, contact.id).status == :invalid
      assert legacy_columns(contact) == Map.put(@legacy_state, :optout_method, "earlier")
    end

    test "number_does_not_exist/2 opts the contact out on its identity" do
      contact = Fixtures.contact_fixture(%{phone: phone()})

      Contacts.number_does_not_exist(contact.id)

      assert %{optout_method: "Number does not exist", optin_status: false} =
               Fixtures.fetch_identity(contact, :whatsapp)
    end
  end

  describe "session status" do
    test "set_session_status/2 follows the contact's opt-in, on the identity" do
      opted_in = Fixtures.contact_fixture(%{phone: phone(), bsp_status: :none})

      not_opted_in =
        Fixtures.contact_fixture(%{
          phone: phone(),
          optin_time: nil,
          optin_status: false,
          bsp_status: :none
        })

      {:ok, _} = Contacts.set_session_status(opted_in, :session)
      {:ok, _} = Contacts.set_session_status(not_opted_in, :session)

      assert Contacts.whatsapp_state(opted_in).bsp_status == :session_and_hsm
      assert Contacts.whatsapp_state(not_opted_in).bsp_status == :session

      {:ok, _} = Contacts.set_session_status(opted_in, :none)
      {:ok, _} = Contacts.set_session_status(not_opted_in, :none)

      assert Contacts.whatsapp_state(opted_in).bsp_status == :hsm
      assert Contacts.whatsapp_state(not_opted_in).bsp_status == :none
    end

    test "set_session_status/2 with :hsm opens the session only within 24 hours of the last message" do
      recent = Fixtures.contact_fixture(%{phone: phone(), last_message_at: DateTime.utc_now()})

      stale =
        Fixtures.contact_fixture(%{
          phone: phone(),
          last_message_at: Timex.shift(DateTime.utc_now(), hours: -30)
        })

      {:ok, _} = Contacts.set_session_status(recent, :hsm)
      {:ok, _} = Contacts.set_session_status(stale, :hsm)

      assert Contacts.whatsapp_state(recent).bsp_status == :session_and_hsm
      assert Contacts.whatsapp_state(stale).bsp_status == :hsm
    end

    test "set_session_status/2 on a pre-identity contact keeps the rest of its state" do
      contact = pre_identity_contact(%{optin_time: @optin_time, bsp_status: :none})

      {:ok, _} = Contacts.set_session_status(contact, :session)

      assert %{bsp_status: :session_and_hsm, optin_time: @optin_time} =
               Fixtures.fetch_identity(contact, :whatsapp)
    end

    test "set_session_status/2 with a list of ids closes every session, with or without an identity" do
      opted_in = Fixtures.contact_fixture(%{phone: phone(), bsp_status: :session_and_hsm})

      not_opted_in =
        Fixtures.contact_fixture(%{
          phone: phone(),
          optin_time: nil,
          optin_status: false,
          bsp_status: :session
        })

      pre_identity =
        pre_identity_contact(%{optin_time: @optin_time, bsp_status: :session_and_hsm})

      assert :ok =
               Contacts.set_session_status([opted_in.id, not_opted_in.id, pre_identity.id], :none)

      assert Contacts.whatsapp_state(opted_in).bsp_status == :hsm
      assert Contacts.whatsapp_state(not_opted_in).bsp_status == :none
      assert Contacts.whatsapp_state(pre_identity).bsp_status == :hsm
    end

    test "set_session_status/2 with a list of ids marks the contacts updated" do
      contact = Fixtures.contact_fixture(%{phone: phone(), bsp_status: :session_and_hsm})
      old = DateTime.add(contact.updated_at, -3600)
      Repo.update_all(from(c in Contact, where: c.id == ^contact.id), set: [updated_at: old])

      assert :ok = Contacts.set_session_status([contact.id], :none)

      assert DateTime.compare(Repo.get!(Contact, contact.id).updated_at, old) == :gt
    end

    test "update_contact_status/2 closes the sessions that are over 24 hours old, on both kinds of contact" do
      stale = Timex.shift(DateTime.utc_now(), hours: -25)
      open = DateTime.utc_now()

      expired =
        Fixtures.contact_fixture(%{
          phone: phone(),
          bsp_status: :session_and_hsm,
          last_message_at: stale
        })

      live =
        Fixtures.contact_fixture(%{
          phone: phone(),
          bsp_status: :session_and_hsm,
          last_message_at: open
        })

      pre_identity_expired =
        pre_identity_contact(%{
          optin_time: @optin_time,
          bsp_status: :session_and_hsm,
          last_message_at: stale
        })

      assert :ok = Contacts.update_contact_status(1, %{})

      assert Contacts.whatsapp_state(expired).bsp_status == :hsm
      assert Contacts.whatsapp_state(live).bsp_status == :session_and_hsm
      assert Contacts.whatsapp_state(pre_identity_expired).bsp_status == :hsm
    end
  end

  describe "can_send_message_to?/3" do
    defp contact_in(state), do: Fixtures.contact_fixture(Map.put(state, :phone, phone()))

    test "a session message needs an open session on the identity" do
      open = contact_in(%{bsp_status: :session_and_hsm})
      closed = contact_in(%{bsp_status: :hsm})

      assert {:ok, nil} = Contacts.can_send_message_to?(open, false)

      assert {:error, "Sorry! 24 hrs window closed" <> _} =
               Contacts.can_send_message_to?(closed, false)
    end

    test "a template message needs an opt-in and a reachable BSP status" do
      opted_in = contact_in(%{bsp_status: :hsm, optin_time: @optin_time})
      unreachable = contact_in(%{bsp_status: :none, optin_time: @optin_time})
      never_opted_in = contact_in(%{bsp_status: :hsm, optin_time: nil, optin_status: false})

      assert {:ok, nil} = Contacts.can_send_message_to?(opted_in, true)

      assert {:error, "Cannot send hsm message to contact, invalid BSP status."} =
               Contacts.can_send_message_to?(unreachable, true)

      assert {:error, "Cannot send hsm message to contact, not opted in."} =
               Contacts.can_send_message_to?(never_opted_in, true)
    end

    test "an opt-out closes the gate" do
      contact = contact_in(%{bsp_status: :hsm, optin_time: @optin_time})
      :ok = Contacts.contact_opted_out(contact.phone, 1, DateTime.utc_now())

      assert {:error, _reason} = Contacts.can_send_message_to?(contact, true)
    end

    test "a pre-identity contact is judged by its own columns" do
      reachable = pre_identity_contact(%{bsp_status: :session_and_hsm, optin_time: @optin_time})
      closed = pre_identity_contact(%{bsp_status: :none, optin_time: nil, optin_status: false})

      assert {:ok, nil} = Contacts.can_send_message_to?(reachable, true)
      assert {:ok, nil} = Contacts.can_send_message_to?(reachable, false)
      assert {:error, _reason} = Contacts.can_send_message_to?(closed, true)
      assert {:error, _reason} = Contacts.can_send_message_to?(closed, false)
    end

    test "an opt-in flow template needs only a BSP status, a session message needs a recent message" do
      hsm = contact_in(%{bsp_status: :hsm})
      session = contact_in(%{bsp_status: :session, last_message_at: DateTime.utc_now()})

      assert {:ok, nil} = Contacts.can_send_message_to?(hsm, true, %{is_optin_flow: true})
      assert {:error, _reason} = Contacts.can_send_message_to?(hsm, false, %{is_optin_flow: true})
      assert {:ok, nil} = Contacts.can_send_message_to?(session, false, %{is_optin_flow: true})
    end

    test "the web OTP is allowed to a contact that was never opted in anywhere" do
      contact = contact_in(%{bsp_status: :none, optin_time: nil, optin_status: false})

      pre_identity =
        pre_identity_contact(%{bsp_status: :none, optin_time: nil, optin_status: false})

      assert {:ok, nil} =
               Contacts.can_send_message_to?(contact, true, %{is_web_channel_otp: true})

      assert {:ok, nil} =
               Contacts.can_send_message_to?(pre_identity, true, %{is_web_channel_otp: true})

      assert {:error, _reason} = Contacts.can_send_message_to?(contact, true)
    end

    test "a blocked contact is refused" do
      contact = contact_in(%{status: :blocked, bsp_status: :session_and_hsm})

      assert {:error, "Contact status is not valid."} =
               Contacts.can_send_message_to?(contact, false)

      assert {:error, _reason} = Contacts.can_send_message_to?(contact, true)
    end
  end

  describe "list_contacts/1 filtered by bsp_status" do
    test "matches the identity's status, or the contact's while it has none" do
      with_identity = contact_in(%{bsp_status: :session})
      without_identity = pre_identity_contact(%{bsp_status: :session})
      other = contact_in(%{bsp_status: :hsm})

      ids =
        %{filter: %{bsp_status: :session}}
        |> Contacts.list_contacts()
        |> Enum.map(& &1.id)

      assert with_identity.id in ids
      assert without_identity.id in ids
      refute other.id in ids

      assert Contacts.count_contacts(%{filter: %{bsp_status: :session}}) >= 2
    end
  end

  describe "filter_not_opted_out/1" do
    test "drops opted-out and blocked contacts, whichever way their state is held" do
      active = contact_in(%{})
      opted_out = contact_in(%{optout_time: @optin_time})
      pre_identity_out = pre_identity_contact(%{optout_time: @optin_time})
      pre_identity_active = pre_identity_contact()
      blocked = contact_in(%{status: :blocked})

      ids =
        [active, opted_out, pre_identity_out, pre_identity_active, blocked] |> Enum.map(& &1.id)

      assert Enum.sort([active.id, pre_identity_active.id]) ==
               ids |> Contacts.filter_not_opted_out() |> Enum.sort()
    end
  end

  describe "the message trigger" do
    defp inbound_message(contact, attrs \\ %{}) do
      Fixtures.message_fixture(
        Map.merge(
          %{
            flow: :inbound,
            sender_id: contact.id,
            receiver_id: Partners.organization_contact_id(1),
            contact_id: contact.id
          },
          attrs
        )
      )
    end

    test "an inbound WhatsApp message starts the session on the identity and, for now, on the contact" do
      contact = Fixtures.contact_fixture(%{phone: phone(), last_message_at: nil})

      inbound_message(contact)

      assert Glific.in_past_time(
               Fixtures.fetch_identity(contact, :whatsapp).last_message_at,
               :seconds,
               10
             )

      assert Glific.in_past_time(legacy_columns(contact).last_message_at, :seconds, 10)
    end

    test "an inbound web message does not" do
      contact = Fixtures.contact_fixture(%{phone: phone(), last_message_at: nil})

      inbound_message(contact, %{channel: :web})

      assert Fixtures.fetch_identity(contact, :whatsapp).last_message_at == nil
      assert legacy_columns(contact).last_message_at == nil
    end

    test "an outbound message does not" do
      contact = Fixtures.contact_fixture(%{phone: phone(), last_message_at: nil})

      inbound_message(contact, %{flow: :outbound})

      assert Fixtures.fetch_identity(contact, :whatsapp).last_message_at == nil
    end

    test "the rest of the inbox state still updates on the contact" do
      contact = Fixtures.contact_fixture(%{phone: phone()})

      Repo.update_all(from(c in Contact, where: c.id == ^contact.id),
        set: [is_org_read: true, last_message_number: 0]
      )

      inbound_message(contact)

      reloaded = Repo.get!(Contact, contact.id)
      assert reloaded.is_org_read == false
      assert reloaded.is_org_replied == false
      assert reloaded.last_message_number == 1
    end

    test "a pre-identity contact gets its identity from its own columns, plus the new session" do
      contact = pre_identity_contact(%{@legacy_state | last_message_at: ~U[2020-01-01 00:00:00Z]})

      inbound_message(contact)

      identity = Fixtures.fetch_identity(contact, :whatsapp)
      assert Glific.in_past_time(identity.last_message_at, :seconds, 10)
      assert identity.optin_time == @optin_time
      assert identity.optin_method == "BSP"
      assert identity.bsp_status == :hsm
      assert identity.optout_method == "earlier"
    end

    test "a contact with no phone has no WhatsApp identity to update" do
      contact = Fixtures.contact_without_phone_fixture()

      inbound_message(contact)

      assert Fixtures.fetch_identity(contact, :whatsapp) == nil
    end
  end
end
