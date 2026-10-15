defmodule Glific.Contacts.ContactIdentityTest do
  use Glific.DataCase

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactIdentity,
    Fixtures,
    Repo
  }

  defp insert_identity(attrs) do
    %ContactIdentity{}
    |> ContactIdentity.changeset(attrs)
    |> Repo.insert()
  end

  defp identifier_errors(organization_id, identifier) do
    contact = Fixtures.contact_without_phone_fixture(%{organization_id: organization_id})

    assert {:error, changeset} =
             insert_identity(%{
               contact_id: contact.id,
               organization_id: organization_id,
               channel: :web,
               identifier: identifier
             })

    errors_on(changeset)
  end

  describe "changeset/2" do
    test "inserts a login for a contact", %{organization_id: organization_id} do
      contact = Fixtures.contact_without_phone_fixture(%{organization_id: organization_id})

      assert {:ok, %ContactIdentity{} = identity} =
               insert_identity(%{
                 contact_id: contact.id,
                 organization_id: organization_id,
                 channel: :web,
                 identifier: "ravi_12"
               })

      assert %{channel: :web, identifier: "ravi_12"} = identity
      assert [%ContactIdentity{id: id}] = Repo.preload(contact, :identities).identities
      assert id == identity.id
    end

    test "requires the contact, organization, channel and identifier" do
      assert {:error, changeset} = insert_identity(%{})

      assert %{
               contact_id: ["can't be blank"],
               organization_id: ["can't be blank"],
               channel: ["can't be blank"],
               identifier: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects an identifier longer than 255 characters", %{organization_id: organization_id} do
      assert %{identifier: ["should be at most 255 character(s)"]} =
               identifier_errors(organization_id, String.duplicate("a", 256))
    end

    test "stores the identifier lowercase", %{organization_id: organization_id} do
      identity =
        Fixtures.contact_identity_fixture(%{
          organization_id: organization_id,
          identifier: "Ravi_Web"
        })

      assert "ravi_web" == identity.identifier
      assert "ravi_web" == Repo.reload!(identity).identifier
    end

    test "accepts letters, digits, underscores, @ and dots", %{organization_id: organization_id} do
      for identifier <- ["ravi", "ravi_12", "ravi.k", "ravi@example.org", "919876543210", "_.@0"] do
        assert %ContactIdentity{identifier: ^identifier} =
                 Fixtures.contact_identity_fixture(%{
                   organization_id: organization_id,
                   identifier: identifier
                 })
      end
    end

    test "rejects any other character", %{organization_id: organization_id} do
      for identifier <- ["ravi web", " ravi", "+919876543210", "ravi-web", "ravi#1", "rävi", ""] do
        assert %{identifier: [_ | _]} = identifier_errors(organization_id, identifier)
      end

      assert %{identifier: ["can only contain letters, numbers, underscores, @ and dots"]} =
               identifier_errors(organization_id, "ravi-web")
    end

    test "keeps a WhatsApp identifier exactly as the phone is stored", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:ok, identity} =
               insert_identity(%{
                 contact_id: contact.id,
                 organization_id: organization_id,
                 channel: :whatsapp,
                 identifier: "+91 98765-43210"
               })

      assert identity.identifier == "+91 98765-43210"
    end

    test "rejects a duplicate identifier on the same channel", %{organization_id: organization_id} do
      Fixtures.contact_identity_fixture(%{
        organization_id: organization_id,
        identifier: "asha_07"
      })

      other = Fixtures.contact_without_phone_fixture(%{organization_id: organization_id})

      assert {:error, changeset} =
               insert_identity(%{
                 contact_id: other.id,
                 organization_id: organization_id,
                 channel: :web,
                 identifier: "asha_07"
               })

      assert %{identifier: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows the same identifier on another channel", %{organization_id: organization_id} do
      identity =
        Fixtures.contact_identity_fixture(%{organization_id: organization_id, identifier: "x"})

      assert {:ok, _} =
               insert_identity(%{
                 contact_id: identity.contact_id,
                 organization_id: organization_id,
                 channel: :whatsapp,
                 identifier: "x"
               })
    end

    test "treats identifiers differing only in case as the same identity", %{
      organization_id: organization_id
    } do
      Fixtures.contact_identity_fixture(%{
        organization_id: organization_id,
        identifier: "ravi_web"
      })

      assert %{identifier: ["has already been taken"]} =
               identifier_errors(organization_id, "Ravi_Web")
    end

    test "rejects a contact that does not exist", %{organization_id: organization_id} do
      assert {:error, changeset} =
               insert_identity(%{
                 contact_id: 0,
                 organization_id: organization_id,
                 channel: :web,
                 identifier: "ghost"
               })

      assert %{contact_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "organization scoping" do
    test "the same identifier can exist in two organizations, and each only sees its own",
         %{organization_id: organization_id} do
      other_org = Fixtures.organization_fixture()

      mine =
        Fixtures.contact_identity_fixture(%{organization_id: organization_id, identifier: "same"})

      theirs =
        Fixtures.contact_identity_fixture(%{organization_id: other_org.id, identifier: "same"})

      Repo.put_organization_id(organization_id)
      ids = ContactIdentity |> Repo.all() |> Enum.map(& &1.id)

      assert mine.id in ids
      refute theirs.id in ids
    end
  end

  describe "deletion" do
    test "deleting a contact deletes its identities", %{organization_id: organization_id} do
      identity = Fixtures.contact_identity_fixture(%{organization_id: organization_id})

      {:ok, _} = Contacts.delete_contact(Repo.get!(Contact, identity.contact_id))

      assert nil == Repo.get(ContactIdentity, identity.id)
    end

    test "deleting an identity leaves the contact", %{organization_id: organization_id} do
      identity = Fixtures.contact_identity_fixture(%{organization_id: organization_id})

      {:ok, _} = Repo.delete(identity)

      assert %Contact{} = Repo.get(Contact, identity.contact_id)
    end
  end
end
