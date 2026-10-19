defmodule Glific.Searches.InboxTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.TermSearch,
    Fixtures,
    Groups,
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

  defp web_linked_contact(attrs) do
    contact = Fixtures.contact_fixture(Map.merge(%{contact_type: "WA"}, attrs))

    Fixtures.contact_identity_fixture(%{
      contact_id: contact.id,
      identifier: "ravi_#{System.unique_integer([:positive])}"
    })

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
      test "a contact with a web identity appears in the #{tab} tab", %{
        organization_id: organization_id
      } do
        contact = web_linked_contact(unquote(Macro.escape(attrs)))

        hidden =
          Fixtures.contact_fixture(Map.merge(%{contact_type: "WA"}, unquote(Macro.escape(attrs))))

        results = search_contact_ids(organization_id, %{status: unquote(tab)})

        assert contact.id in results
        refute hidden.id in results
      end
    end
  end

  describe "search by identifier" do
    test "a manager finds a contact by the start of its username, in any case", %{
      organization_id: organization_id
    } do
      contact = username_contact()

      assert contact.id in search_contact_ids(organization_id, %{term: "RAVI_1"})
      assert contact.id in search_contact_ids(organization_id, %{term: "ravi"})
    end

    test "a username is not matched in the middle", %{organization_id: organization_id} do
      contact = username_contact()

      refute contact.id in search_contact_ids(organization_id, %{term: "avi_12"})
      refute contact.id in search_contact_ids(organization_id, %{term: "12"})
    end

    test "_ and % in the term match literally", %{organization_id: organization_id} do
      [literal, underscore_wildcard, percent_wildcard] =
        for username <- ["ravi_1x", "ravix1", "ravi21"] do
          contact = Fixtures.contact_without_phone_fixture()
          Fixtures.contact_identity_fixture(%{contact_id: contact.id, identifier: username})
          contact
        end

      results = search_contact_ids(organization_id, %{term: "ravi_1"})

      assert literal.id in results
      refute underscore_wildcard.id in results
      refute percent_wildcard.id in results
      refute literal.id in search_contact_ids(organization_id, %{term: "%"})
      refute literal.id in search_contact_ids(organization_id, %{term: "ravi%"})
    end

    test "a staff user does not find a contact by its username", %{
      organization_id: organization_id
    } do
      contact = username_contact()
      Repo.put_current_user(Fixtures.user_fixture(%{roles: ["staff"]}))

      refute contact.id in search_contact_ids(organization_id, %{term: "ravi_12"})
    end

    test "a blocked contact is not found by its username or name", %{
      organization_id: organization_id
    } do
      contact = username_contact(%{name: "Blocked Ravi", status: :blocked})

      refute contact.id in search_contact_ids(organization_id, %{term: "ravi_12"})
      refute contact.id in search_contact_ids(organization_id, %{term: "Blocked Ravi"})
    end

    test "a restricted staff user finds a name match only within their groups", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{roles: ["staff"], is_restricted: true})
      group = Fixtures.group_fixture(%{label: "Ravi group"})

      {:ok, _user_group} =
        Groups.create_user_group(%{
          user_id: user.id,
          group_id: group.id,
          organization_id: organization_id
        })

      visible = Fixtures.contact_fixture(%{name: "Zorbax visible"})
      hidden = Fixtures.contact_fixture(%{name: "Zorbax hidden"})

      {:ok, _contact_group} =
        Groups.create_contact_group(%{
          contact_id: visible.id,
          group_id: group.id,
          organization_id: organization_id
        })

      Repo.put_current_user(user)
      results = search_contact_ids(organization_id, %{term: "Zorbax"})

      assert visible.id in results
      refute hidden.id in results
    end

    test "the username match stays within the organization of the outer query", %{
      organization_id: organization_id
    } do
      other_organization = Fixtures.organization_fixture()

      other =
        Fixtures.contact_without_phone_fixture(%{organization_id: other_organization.id})

      Fixtures.contact_identity_fixture(%{
        contact_id: other.id,
        organization_id: other_organization.id,
        identifier: "ravi_12"
      })

      Repo.put_organization_id(organization_id)

      matched =
        Contact
        |> where(^TermSearch.match("ravi_12", Repo.get_current_user()))
        |> select([c], c.id)
        |> Repo.all(skip_organization_id: true)

      refute other.id in matched
    end

    test "the username match takes the organization from the user, not the process", %{
      organization_id: organization_id
    } do
      contact = username_contact()
      user = Repo.get_current_user()

      # A multi-search task on the read replica has no Glific.Repo organization set.
      Repo.put_organization_id(nil)
      condition = TermSearch.match("ravi_12", user)
      Repo.put_organization_id(organization_id)

      matched =
        Contact
        |> where(^condition)
        |> select([c], c.id)
        |> Repo.all()

      assert contact.id in matched
    end

    test "no username is matched for a user with string staff roles or no roles" do
      contact = username_contact()
      user = Repo.get_current_user()

      for roles <- [["staff"], nil] do
        matched =
          Contact
          |> where(^TermSearch.match("ravi_12", %{user | roles: roles}))
          |> select([c], c.id)
          |> Repo.all()

        refute contact.id in matched
      end
    end

    test "no username is matched without a user", %{organization_id: organization_id} do
      contact = username_contact()

      matched =
        Contact
        |> where(^TermSearch.match("ravi_12", nil))
        |> select([c], c.id)
        |> Repo.all()

      refute contact.id in matched
      assert organization_id == contact.organization_id
    end
  end
end
