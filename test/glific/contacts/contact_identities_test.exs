defmodule Glific.Contacts.ContactIdentitiesTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactIdentities,
    Contacts.ContactIdentity,
    Fixtures,
    Partners,
    Repo
  }

  defp identities_of(contact_id) do
    ContactIdentity
    |> where([i], i.contact_id == ^contact_id)
    |> order_by([i], i.id)
    |> Repo.all()
  end

  defp whatsapp_identity(phone) do
    Repo.get_by(ContactIdentity, %{channel: :whatsapp, identifier: phone})
  end

  describe "maybe_create_contact/3 on web" do
    test "an unknown identifier creates a contact with no phone, and its identity" do
      assert {:ok, %Contact{} = contact} = Contacts.maybe_create_contact(%{}, :web, "ravi_12")

      assert contact.phone == nil
      assert contact.name == "ravi_12"

      assert [%{channel: :web, identifier: "ravi_12"}] =
               identities_of(contact.id)
    end

    test "an identifier the identity changeset rejects returns the error and creates no contact" do
      contacts_before = Repo.aggregate(Contact, :count)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Contacts.maybe_create_contact(%{name: "Ravi"}, :web, String.duplicate("a", 256))

      assert %{identifier: [_too_long]} = errors_on(changeset)
      assert Repo.aggregate(Contact, :count) == contacts_before
    end

    test "uses the name claim as the contact's name" do
      assert {:ok, contact} = Contacts.maybe_create_contact(%{name: "Ravi"}, :web, "ravi_12")
      assert contact.name == "Ravi"
    end

    test "identifiers differing only in case are the same contact" do
      {:ok, first} = Contacts.maybe_create_contact(%{}, :web, "Ravi_Web")
      assert {:ok, second} = Contacts.maybe_create_contact(%{}, :web, "ravi_web")

      assert first.id == second.id
      assert length(identities_of(first.id)) == 1
      assert {:ok, found} = Contacts.fetch_by_identity(:web, "RAVI_WEB")
      assert found.id == first.id
    end

    test "a known identifier returns the same contact" do
      {:ok, first} = Contacts.maybe_create_contact(%{}, :web, "ravi_12")
      assert {:ok, second} = Contacts.maybe_create_contact(%{}, :web, "ravi_12")

      assert first.id == second.id
      assert length(identities_of(first.id)) == 1
    end

    test "the claims are ignored for a known identifier", %{organization_id: organization_id} do
      {:ok, existing} = Contacts.maybe_create_contact(%{}, :web, "ravi_12")
      other = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, resolved} =
               Contacts.maybe_create_contact(
                 %{phone: other.phone, name: "Someone Else"},
                 :web,
                 "ravi_12"
               )

      assert resolved.id == existing.id
      assert identities_of(other.id) |> Enum.all?(&(&1.channel == :whatsapp))
    end

    test "the phone claim links to the WhatsApp contact with that phone", %{
      organization_id: organization_id
    } do
      target = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, contact} =
               Contacts.maybe_create_contact(%{phone: target.phone}, :web, "ravi_12")

      assert contact.id == target.id
      assert [:whatsapp, :web] = identities_of(target.id) |> Enum.map(& &1.channel)
    end

    test "a contact may have several web identities", %{organization_id: organization_id} do
      target = Fixtures.contact_fixture(%{organization_id: organization_id})

      {:ok, _} = Contacts.maybe_create_contact(%{phone: target.phone}, :web, "first")
      {:ok, _} = Contacts.maybe_create_contact(%{phone: target.phone}, :web, "second")

      assert 2 == identities_of(target.id) |> Enum.count(&(&1.channel == :web))
    end

    test "a phone claim no contact has becomes the new contact's phone, without a WhatsApp identity" do
      phone = "919876543210"

      assert {:ok, contact} = Contacts.maybe_create_contact(%{phone: phone}, :web, "ravi_12")

      assert contact.phone == phone
      assert nil == whatsapp_identity(phone)
    end

    test "that phone gets its WhatsApp identity when it first messages on WhatsApp", %{
      organization_id: organization_id
    } do
      phone = "919876543211"
      {:ok, contact} = Contacts.maybe_create_contact(%{phone: phone}, :web, "ravi_13")

      assert {:ok, %{id: id}} = Contacts.fetch_by_identity(:whatsapp, phone)
      assert id == contact.id
      assert nil == whatsapp_identity(phone)

      assert {:ok, %{id: ^id}} =
               Contacts.maybe_create_contact(%{
                 phone: phone,
                 name: contact.name,
                 organization_id: organization_id
               })

      assert whatsapp_identity(phone).contact_id == contact.id
    end

    test "a phone another web login stored but WhatsApp never confirmed is not linked to" do
      phone = "919876543212"
      {:ok, asha} = Contacts.maybe_create_contact(%{phone: phone}, :web, "asha_07")

      assert {:ok, ravi} = Contacts.maybe_create_contact(%{phone: phone}, :web, "ravi_12")

      refute ravi.id == asha.id
      assert ravi.phone == nil
      assert nil == whatsapp_identity(phone)
    end

    test "a staff-created contact is linked to even if it has never messaged", %{
      organization_id: organization_id
    } do
      {:ok, created} =
        Contacts.create_contact(%{
          organization_id: organization_id,
          name: "Imported",
          phone: "919876543213"
        })

      assert nil == created.last_message_at

      assert {:ok, contact} =
               Contacts.maybe_create_contact(%{phone: created.phone}, :web, "ravi_15")

      assert contact.id == created.id
    end

    test "a WhatsApp contact that has messaged is linked to before it has an identity", %{
      organization_id: organization_id
    } do
      target = Fixtures.contact_fixture(%{organization_id: organization_id})
      Repo.delete_all(from(i in ContactIdentity, where: i.contact_id == ^target.id))

      Repo.update_all(from(c in Contact, where: c.id == ^target.id),
        set: [last_message_at: DateTime.utc_now()]
      )

      assert {:ok, contact} =
               Contacts.maybe_create_contact(%{phone: target.phone}, :web, "ravi_14")

      assert contact.id == target.id
    end

    test "a phone claim naming the organization's own contact creates a contact without it", %{
      organization_id: organization_id
    } do
      org_contact =
        Repo.get!(Contact, Partners.organization_contact_id(organization_id))

      assert {:ok, contact} =
               Contacts.maybe_create_contact(%{phone: org_contact.phone}, :web, "bot_phone")

      refute contact.id == org_contact.id
      assert contact.phone == nil
      refute Enum.any?(identities_of(org_contact.id), &(&1.channel == :web))
    end

    test "a simulator phone claim creates a contact without that phone", %{
      organization_id: organization_id
    } do
      phone = Contacts.simulator_phone_prefix() <> "2"

      assert {:ok, fresh} = Contacts.maybe_create_contact(%{phone: phone}, :web, "sim_phone_a")
      assert fresh.phone == nil

      simulator = Fixtures.contact_fixture(%{organization_id: organization_id, phone: phone})
      assert {:ok, contact} = Contacts.maybe_create_contact(%{phone: phone}, :web, "sim_phone_b")

      refute contact.id == simulator.id
      assert contact.phone == nil
    end

    test "concurrent first logins give one contact and one identity" do
      organization_id = Repo.get_organization_id()

      contact_ids =
        1..4
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Repo.put_organization_id(organization_id)
            {:ok, contact} = Contacts.maybe_create_contact(%{}, :web, "same_tab")
            contact.id
          end)
        end)
        |> Task.await_many()
        |> Enum.uniq()

      assert [contact_id] = contact_ids
      assert [%{identifier: "same_tab"}] = identities_of(contact_id)

      assert 1 ==
               ContactIdentity
               |> where([i], i.identifier == "same_tab")
               |> Repo.aggregate(:count)
    end

    test "the same identifier in another organization is a different contact", %{
      organization_id: organization_id
    } do
      other_organization = Fixtures.organization_fixture()
      Repo.put_organization_id(organization_id)
      {:ok, here} = Contacts.maybe_create_contact(%{}, :web, "shared")

      Repo.put_organization_id(other_organization.id)
      {:ok, there} = Contacts.maybe_create_contact(%{}, :web, "shared")

      refute here.id == there.id
      assert there.organization_id == other_organization.id
    end
  end

  describe "insert_contacts/2" do
    test "writes the contacts and their WhatsApp identities", %{organization_id: organization_id} do
      now = DateTime.utc_now()

      entries =
        for phone <- ["919876500801", "919876500802"],
            do: %{
              phone: phone,
              name: "Bulk",
              language_id: 1,
              organization_id: organization_id,
              inserted_at: now,
              updated_at: now
            }

      saved =
        Contacts.insert_contacts(entries,
          on_conflict: :nothing,
          organization_id: organization_id
        )

      assert [%{phone: "919876500801"}, %{phone: "919876500802"}] =
               Enum.sort_by(saved, & &1.phone)

      for %{id: id, phone: phone} <- saved do
        assert %{contact_id: ^id} = whatsapp_identity(phone)
      end
    end
  end

  describe "add_identity/3" do
    test "only web usernames can be added", %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:error, %Ecto.Changeset{errors: [channel: _]}} =
               Contacts.add_identity(contact, :whatsapp, contact.phone)
    end

    test "adds a username once and is idempotent for the same contact", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, _} = Contacts.add_identity(contact, :web, "Added_User")
      assert {:ok, _} = Contacts.add_identity(contact, :web, "added_user")
      assert {:ok, found} = Contacts.fetch_by_identity(:web, "added_user")
      assert found.id == contact.id
    end

    test "never moves a username held by another contact", %{organization_id: organization_id} do
      owner = Fixtures.contact_fixture(%{organization_id: organization_id})
      other = Fixtures.contact_fixture(%{organization_id: organization_id})
      {:ok, _} = Contacts.add_identity(owner, :web, "held")

      assert {:error, changeset} = Contacts.add_identity(other, :web, "held")
      assert %{identifier: ["has already been taken"]} = errors_on(changeset)
      assert {:ok, %{id: id}} = Contacts.fetch_by_identity(:web, "held")
      assert id == owner.id
    end
  end

  describe "create_contact/1 with a channel" do
    test "a WhatsApp contact and its identity are created together", %{
      organization_id: organization_id
    } do
      attrs = %{organization_id: organization_id, phone: "919876500002", name: "Together"}

      assert {:ok, contact} =
               Contacts.create_contact(attrs)

      assert [%{channel: :whatsapp, identifier: "919876500002"}] = identities_of(contact.id)
    end

    test "a WhatsApp contact's identity is its phone, whatever identifier is given", %{
      organization_id: organization_id
    } do
      attrs = %{organization_id: organization_id, phone: "919876500006", name: "Phone wins"}

      assert {:ok, contact} = Contacts.create_contact(attrs, :whatsapp, "not_the_phone")

      assert [%{channel: :whatsapp, identifier: "919876500006"}] = identities_of(contact.id)
    end

    test "a web contact with a phone keeps the phone and gets only its web identity", %{
      organization_id: organization_id
    } do
      attrs = %{organization_id: organization_id, phone: "919876500003", name: "Both"}

      assert {:ok, contact} =
               Contacts.create_contact(attrs, :web, "both_user")

      assert contact.phone == "919876500003"

      assert [{:web, "both_user"}] =
               contact.id |> identities_of() |> Enum.map(&{&1.channel, &1.identifier})
    end

    test "an identity that fails leaves no contact behind", %{organization_id: organization_id} do
      contact_count = Repo.aggregate(Contact, :count)
      attrs = %{organization_id: organization_id, name: "Orphan"}

      assert {:error, %Ecto.Changeset{data: %ContactIdentity{}}} =
               Contacts.create_contact(attrs, :web, "not valid!")

      assert contact_count == Repo.aggregate(Contact, :count)
    end
  end

  describe "WhatsApp identities" do
    test "create_contact/1 records the identity", %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert %{contact_id: contact_id, organization_id: ^organization_id} =
               whatsapp_identity(contact.phone)

      assert contact_id == contact.id
    end

    test "create_contact/1 with invalid data records nothing", %{organization_id: organization_id} do
      identity_count = Repo.aggregate(ContactIdentity, :count)

      assert {:error, %Ecto.Changeset{}} =
               Contacts.create_contact(%{organization_id: organization_id, phone: nil})

      assert identity_count == Repo.aggregate(ContactIdentity, :count)
    end

    test "upsert/1 records the identity once", %{organization_id: organization_id} do
      attrs = %{organization_id: organization_id, phone: "919876500001", name: "Upserted"}

      {:ok, first} = Contacts.upsert(attrs)
      {:ok, second} = Contacts.upsert(%{attrs | name: "Renamed"})

      assert first.id == second.id
      assert whatsapp_identity("919876500001").contact_id == first.id

      assert 1 ==
               ContactIdentity
               |> where([i], i.identifier == "919876500001")
               |> Repo.aggregate(:count)
    end

    test "upsert/1 leaves last_communication_at unset on a new contact", %{
      organization_id: organization_id
    } do
      {:ok, contact} =
        Contacts.upsert(%{organization_id: organization_id, phone: "919876500007", name: "Quiet"})

      assert nil == Repo.reload!(contact).last_communication_at
    end

    test "changing the phone moves the identity", %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})
      old_phone = contact.phone

      assert {:ok, updated} = Contacts.update_contact(contact, %{phone: "919876500002"})

      assert updated.phone == "919876500002"
      assert nil == whatsapp_identity(old_phone)
      assert whatsapp_identity("919876500002").contact_id == contact.id
    end

    test "a contact holding two WhatsApp rows can still change its phone", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      Repo.insert!(%ContactIdentity{
        contact_id: contact.id,
        organization_id: organization_id,
        channel: :whatsapp,
        identifier: "919876500004"
      })

      assert {:ok, _updated} = Contacts.update_contact(contact, %{phone: "919876500005"})

      assert [%{identifier: "919876500005"}] =
               from(i in ContactIdentity,
                 where: i.contact_id == ^contact.id and i.channel == :whatsapp
               )
               |> Repo.all()
    end

    test "a failed phone change leaves the identity alone", %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})
      taken = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:error, %Ecto.Changeset{}} = Contacts.update_contact(contact, %{phone: taken.phone})
      assert whatsapp_identity(contact.phone).contact_id == contact.id
    end

    test "a web contact given a phone gets a WhatsApp identity", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_without_phone_fixture(%{organization_id: organization_id})

      assert {:ok, _} = Contacts.update_contact(contact, %{phone: "919876500003"})

      assert whatsapp_identity("919876500003").contact_id == contact.id
    end

    test "set_whatsapp_identity takes over a stale row for the same phone", %{
      organization_id: organization_id
    } do
      stale = Fixtures.contact_fixture(%{organization_id: organization_id})
      other = Fixtures.contact_without_phone_fixture(%{organization_id: organization_id})
      phone = stale.phone
      Repo.update_all(from(c in Contact, where: c.id == ^stale.id), set: [phone: "919876500010"])
      {:ok, other} = Contacts.update_contact(other, %{phone: phone})

      assert whatsapp_identity(phone).contact_id == other.id
      assert :ok = ContactIdentities.set_whatsapp_identity(other)
      assert whatsapp_identity(phone).contact_id == other.id
    end

    test "an update that leaves the phone alone does not touch identities", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})
      before = whatsapp_identity(contact.phone)

      assert {:ok, _} = Contacts.update_contact(contact, %{name: "New name"})
      assert whatsapp_identity(contact.phone) == before
    end
  end

  describe "fetch_by_identity/2" do
    test "whatsapp ignores a stale identity and finds the real owner, who takes over the row when it messages",
         %{
           organization_id: organization_id
         } do
      stale_owner = Fixtures.contact_fixture(%{organization_id: organization_id})
      owner = Fixtures.contact_fixture(%{organization_id: organization_id})
      phone = owner.phone
      Repo.delete_all(from(i in ContactIdentity, where: i.contact_id == ^owner.id))

      Repo.update_all(from(c in Contact, where: c.id == ^stale_owner.id),
        set: [phone: "919876500009"]
      )

      Repo.update_all(
        from(i in ContactIdentity, where: i.contact_id == ^stale_owner.id),
        set: [identifier: phone]
      )

      assert {:error, :not_found} = ContactIdentities.fetch_contact(:whatsapp, phone)
      assert {:ok, found} = Contacts.fetch_by_identity(:whatsapp, phone)
      assert found.id == owner.id
      assert whatsapp_identity(phone).contact_id == stale_owner.id

      assert {:ok, _owner} =
               Contacts.maybe_create_contact(%{
                 phone: phone,
                 name: owner.name,
                 organization_id: organization_id
               })

      assert whatsapp_identity(phone).contact_id == owner.id
    end

    test "whatsapp falls back to the phone column without writing an identity", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})
      Repo.delete_all(ContactIdentity)
      assert nil == whatsapp_identity(contact.phone)

      assert {:ok, found} = Contacts.fetch_by_identity(:whatsapp, contact.phone)

      assert found.id == contact.id
      assert nil == whatsapp_identity(contact.phone)
    end

    test "identifier_taken? is false for a taken contact phone", %{
      organization_id: organization_id
    } do
      taken = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:error, changeset} =
               Contacts.create_contact(%{
                 organization_id: organization_id,
                 name: "Same phone",
                 phone: taken.phone
               })

      refute ContactIdentities.identifier_taken?(changeset)
    end

    test "whatsapp of an unknown phone is not found" do
      assert {:error, :not_found} = Contacts.fetch_by_identity(:whatsapp, "919000000000")
    end

    test "web finds the contact by identifier" do
      {:ok, contact} = Contacts.maybe_create_contact(%{}, :web, "ravi_12")

      assert {:ok, found} = Contacts.fetch_by_identity(:web, "ravi_12")
      assert found.id == contact.id
      assert {:ok, ^found} = Contacts.fetch_by_identity(:web, "Ravi_12")
      assert {:error, :not_found} = Contacts.fetch_by_identity(:web, "someone_else")
    end

    test "a nil or empty identifier is refused" do
      assert {:error, :no_identifier} = Contacts.fetch_by_identity(:whatsapp, nil)
      assert {:error, :no_identifier} = Contacts.fetch_by_identity(:web, "")
    end
  end
end
