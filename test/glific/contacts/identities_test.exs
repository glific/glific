defmodule Glific.Contacts.IdentitiesTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactIdentity,
    Contacts.Identities,
    Fixtures,
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

  describe "resolve_or_create/3" do
    test "an unknown identifier creates a contact with no phone, and its identity" do
      assert {:ok, %Contact{} = contact} = Identities.resolve_or_create(:web, "ravi_12", %{})

      assert contact.phone == nil
      assert contact.name == "ravi_12"

      assert [%{channel: :web, identifier: "ravi_12"}] =
               identities_of(contact.id)
    end

    test "an identifier the identity changeset rejects returns the error and creates no contact" do
      contacts_before = Repo.aggregate(Contact, :count)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Identities.resolve_or_create(:web, String.duplicate("a", 256), %{name: "Ravi"})

      assert %{identifier: [_too_long]} = errors_on(changeset)
      assert Repo.aggregate(Contact, :count) == contacts_before
    end

    test "uses the name claim as the contact's name" do
      assert {:ok, contact} = Identities.resolve_or_create(:web, "ravi_12", %{name: "Ravi"})
      assert contact.name == "Ravi"
    end

    test "identifiers differing only in case are the same contact" do
      {:ok, first} = Identities.resolve_or_create(:web, "Ravi_Web", %{})
      assert {:ok, second} = Identities.resolve_or_create(:web, "ravi_web", %{})

      assert first.id == second.id
      assert length(identities_of(first.id)) == 1
      assert {:ok, found} = Identities.fetch_contact(:web, "RAVI_WEB")
      assert found.id == first.id
    end

    test "a known identifier returns the same contact" do
      {:ok, first} = Identities.resolve_or_create(:web, "ravi_12", %{})
      assert {:ok, second} = Identities.resolve_or_create(:web, "ravi_12", %{})

      assert first.id == second.id
      assert length(identities_of(first.id)) == 1
    end

    test "the claims are ignored for a known identifier", %{organization_id: organization_id} do
      {:ok, existing} = Identities.resolve_or_create(:web, "ravi_12", %{})
      other = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, resolved} =
               Identities.resolve_or_create(:web, "ravi_12", %{
                 contact_id: other.id,
                 phone: other.phone,
                 name: "Someone Else"
               })

      assert resolved.id == existing.id
      assert identities_of(other.id) |> Enum.all?(&(&1.channel == :whatsapp))
    end

    test "the contact_id claim links to a contact of the same organization", %{
      organization_id: organization_id
    } do
      target = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, contact} =
               Identities.resolve_or_create(:web, "ravi_12", %{contact_id: target.id})

      assert contact.id == target.id
      assert [:whatsapp, :web] = identities_of(target.id) |> Enum.map(& &1.channel)
    end

    test "a contact may have several web identities", %{organization_id: organization_id} do
      target = Fixtures.contact_fixture(%{organization_id: organization_id})

      {:ok, _} = Identities.resolve_or_create(:web, "first", %{contact_id: target.id})
      {:ok, _} = Identities.resolve_or_create(:web, "second", %{contact_id: target.id})

      assert 2 == identities_of(target.id) |> Enum.count(&(&1.channel == :web))
    end

    test "a contact_id of another organization is not a target and is not revealed", %{
      organization_id: organization_id
    } do
      other_organization = Fixtures.organization_fixture()
      foreign = Fixtures.contact_fixture(%{organization_id: other_organization.id})
      Repo.put_organization_id(organization_id)

      assert {:ok, contact} =
               Identities.resolve_or_create(:web, "ravi_12", %{contact_id: foreign.id})

      refute contact.id == foreign.id
      assert contact.phone == nil
      assert identities_of(foreign.id) |> Enum.all?(&(&1.channel == :whatsapp))
    end

    test "an unknown contact_id falls through to no target" do
      assert {:ok, contact} = Identities.resolve_or_create(:web, "ravi_12", %{contact_id: 0})
      assert contact.phone == nil
    end

    test "the phone claim links to an existing WhatsApp contact", %{
      organization_id: organization_id
    } do
      target = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, contact} =
               Identities.resolve_or_create(:web, "ravi_12", %{phone: target.phone})

      assert contact.id == target.id
    end

    test "contact_id wins over the phone claim", %{organization_id: organization_id} do
      by_id = Fixtures.contact_fixture(%{organization_id: organization_id})
      by_phone = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, contact} =
               Identities.resolve_or_create(:web, "ravi_12", %{
                 contact_id: by_id.id,
                 phone: by_phone.phone
               })

      assert contact.id == by_id.id
    end

    test "an unclaimed phone claim becomes the new contact's phone, without a WhatsApp identity" do
      phone = "919876543210"

      assert {:ok, contact} = Identities.resolve_or_create(:web, "ravi_12", %{phone: phone})

      assert contact.phone == phone
      assert nil == whatsapp_identity(phone)
    end

    test "that phone gets its WhatsApp identity when it first messages on WhatsApp" do
      phone = "919876543211"
      {:ok, contact} = Identities.resolve_or_create(:web, "ravi_13", %{phone: phone})

      assert {:ok, %{id: id}} = Contacts.fetch_by_identity(:whatsapp, phone)
      assert id == contact.id
      assert whatsapp_identity(phone).contact_id == contact.id
    end

    test "concurrent first logins give one contact and one identity" do
      organization_id = Repo.get_organization_id()

      contact_ids =
        1..4
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Repo.put_organization_id(organization_id)
            {:ok, contact} = Identities.resolve_or_create(:web, "same_tab", %{})
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
      {:ok, here} = Identities.resolve_or_create(:web, "shared", %{})

      Repo.put_organization_id(other_organization.id)
      {:ok, there} = Identities.resolve_or_create(:web, "shared", %{})

      refute here.id == there.id
      assert there.organization_id == other_organization.id
    end
  end

  describe "create_contact_with_identity/4" do
    test "a WhatsApp contact and its identity are created together", %{
      organization_id: organization_id
    } do
      attrs = %{organization_id: organization_id, phone: "919876500002", name: "Together"}

      assert {:ok, contact} =
               Identities.create_contact_with_identity(attrs, :whatsapp, attrs.phone)

      assert [%{channel: :whatsapp, identifier: "919876500002"}] = identities_of(contact.id)
    end

    test "a web contact with a phone keeps the phone and gets only its web identity", %{
      organization_id: organization_id
    } do
      attrs = %{organization_id: organization_id, phone: "919876500003", name: "Both"}

      assert {:ok, contact} = Identities.create_contact_with_identity(attrs, :web, "both_user")

      assert contact.phone == "919876500003"

      assert [{:web, "both_user"}] =
               contact.id |> identities_of() |> Enum.map(&{&1.channel, &1.identifier})
    end

    test "an identity that fails leaves no contact behind", %{organization_id: organization_id} do
      contact_count = Repo.aggregate(Contact, :count)
      attrs = %{organization_id: organization_id, name: "Orphan"}

      assert {:error, %Ecto.Changeset{data: %ContactIdentity{}}} =
               Identities.create_contact_with_identity(attrs, :web, "not valid!")

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

    test "changing the phone moves the identity", %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})
      old_phone = contact.phone
      identity_id = whatsapp_identity(old_phone).id

      assert {:ok, updated} = Contacts.update_contact(contact, %{phone: "919876500002"})

      assert updated.phone == "919876500002"
      assert nil == whatsapp_identity(old_phone)
      assert %{id: ^identity_id} = whatsapp_identity("919876500002")
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
    test "whatsapp reads the identity, whatever the contact's phone column says", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      Repo.update_all(from(c in Contact, where: c.id == ^contact.id),
        set: [phone: "919876500009"]
      )

      assert {:ok, found} = Contacts.fetch_by_identity(:whatsapp, contact.phone)
      assert found.id == contact.id
    end

    test "whatsapp falls back to the phone column and records the missing identity", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})
      Repo.delete_all(ContactIdentity)
      assert nil == whatsapp_identity(contact.phone)

      assert {:ok, found} = Contacts.fetch_by_identity(:whatsapp, contact.phone)

      assert found.id == contact.id
      assert whatsapp_identity(contact.phone).contact_id == contact.id
    end

    test "whatsapp of an unknown phone is not found" do
      assert {:error, :not_found} = Contacts.fetch_by_identity(:whatsapp, "919000000000")
    end

    test "web finds the contact by identifier" do
      {:ok, contact} = Identities.resolve_or_create(:web, "ravi_12", %{})

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

  describe "list_contacts/1 term filter" do
    setup do
      contact = Fixtures.contact_without_phone_fixture(%{name: "Asha"})
      Fixtures.contact_identity_fixture(%{contact_id: contact.id, identifier: "asha_07"})
      %{contact: contact}
    end

    test "matches a web identifier for a manager, in any case", %{contact: contact} do
      ids = %{filter: %{term: "ASHA_0"}} |> Contacts.list_contacts() |> Enum.map(& &1.id)

      assert contact.id in ids
    end

    test "does not match a web identifier for a staff user", %{contact: contact} do
      Repo.put_current_user(Fixtures.user_fixture(%{roles: ["staff"]}))

      ids = %{filter: %{term: "asha_07"}} |> Contacts.list_contacts() |> Enum.map(& &1.id)

      refute contact.id in ids
    end

    test "does not match a whatsapp identifier that is not a name or phone", %{contact: contact} do
      Fixtures.contact_identity_fixture(%{
        contact_id: contact.id,
        channel: :whatsapp,
        identifier: "wa_only_key"
      })

      ids = %{filter: %{term: "wa_only_key"}} |> Contacts.list_contacts() |> Enum.map(& &1.id)

      refute contact.id in ids
    end
  end
end
