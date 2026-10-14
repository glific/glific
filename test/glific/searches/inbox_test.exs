defmodule Glific.Searches.InboxTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Repo,
    Searches
  }

  defp search_contact_ids(organization_id, filter) do
    %{
      filter: Map.put(filter, :organization_id, organization_id),
      contact_opts: %{limit: 50, offset: 0},
      message_opts: %{limit: 10, offset: 0}
    }
    |> Searches.search(false)
    |> Enum.map(& &1.contact.id)
  end

  defp username_contact(attrs \\ %{}) do
    contact = Fixtures.contact_without_phone_fixture(attrs)
    Fixtures.contact_identity_fixture(%{contact_id: contact.id, identifier: "ravi_12"})
    contact
  end

  describe "inbox visibility" do
    test "a username contact appears in the main list", %{organization_id: organization_id} do
      contact = username_contact()

      assert contact.id in search_contact_ids(organization_id, %{})
      assert contact.id in search_contact_ids(organization_id, %{term: contact.name})
    end

    test "a phone-less contact without an identity stays hidden", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_without_phone_fixture()

      refute contact.id in search_contact_ids(organization_id, %{})
    end

    test "a contact with only a whatsapp identity stays hidden", %{
      organization_id: organization_id
    } do
      contact = Fixtures.contact_fixture(%{contact_type: "WA"})
      Fixtures.contact_identity_fixture(%{contact_id: contact.id, channel: :whatsapp})

      refute contact.id in search_contact_ids(organization_id, %{})
    end

    test "a WABA contact with a web identity appears once", %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture(%{contact_type: "WABA"})
      Fixtures.contact_identity_fixture(%{contact_id: contact.id})
      Fixtures.contact_identity_fixture(%{contact_id: contact.id})

      assert [contact.id] ==
               organization_id
               |> search_contact_ids(%{})
               |> Enum.filter(&(&1 == contact.id))
    end

    for {tab, attrs} <- [
          {"Unread", %{is_org_read: false}},
          {"Optin", %{optin_status: true}},
          {"Optout", %{optout_time: ~U[2026-01-01 00:00:00Z]}},
          {"Not replied", %{is_org_replied: false}},
          {"Not Responded", %{is_contact_replied: false}}
        ] do
      test "a username contact appears in the #{tab} tab", %{organization_id: organization_id} do
        contact = username_contact(unquote(Macro.escape(attrs)))
        hidden = Fixtures.contact_without_phone_fixture(unquote(Macro.escape(attrs)))

        results = search_contact_ids(organization_id, %{status: unquote(tab)})

        assert contact.id in results
        refute hidden.id in results
      end
    end
  end

  describe "search by identifier" do
    test "a manager finds a contact by a part of its username, in any case", %{
      organization_id: organization_id
    } do
      contact = username_contact()

      assert contact.id in search_contact_ids(organization_id, %{term: "AVI_1"})
    end

    test "a staff user does not find a contact by its username", %{
      organization_id: organization_id
    } do
      contact = username_contact()
      Repo.put_current_user(Fixtures.user_fixture(%{roles: ["staff"]}))

      refute contact.id in search_contact_ids(organization_id, %{term: "ravi_12"})
    end

    test "another organization's identity is not matched", %{organization_id: organization_id} do
      other_organization = Fixtures.organization_fixture()

      other =
        Fixtures.contact_without_phone_fixture(%{organization_id: other_organization.id})

      Fixtures.contact_identity_fixture(%{
        contact_id: other.id,
        organization_id: other_organization.id,
        identifier: "ravi_12"
      })

      Repo.put_organization_id(organization_id)

      refute other.id in search_contact_ids(organization_id, %{term: "ravi_12"})
    end
  end
end
