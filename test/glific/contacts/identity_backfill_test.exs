defmodule Glific.Contacts.IdentityBackfillTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
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

  defp contact_without_identity(attrs \\ %{}) do
    contact = Fixtures.contact_fixture(Map.merge(%{phone: phone()}, attrs))

    Repo.delete_all(from(i in ContactIdentity, where: i.contact_id == ^contact.id),
      skip_organization_id: true
    )

    contact
  end

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
end
