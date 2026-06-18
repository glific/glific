defmodule Glific.Groups.ContactWAGroupsTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
        "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
      },
      is_active: true
    })

    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization.id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization.id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    %{organization_id: organization.id, wa_managed_phone: wa_managed_phone, wa_group: wa_group}
  end

  defp mock_success do
    Tesla.Mock.mock(fn %{method: :post} ->
      {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}
    end)
  end

  describe "modify_members/4" do
    test "adds members when only add ids are given", %{
      wa_group: wa_group,
      wa_managed_phone: phone,
      organization_id: org_id
    } do
      mock_success()
      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      assert {:ok, %{added: 1, removed: 0}} =
               ContactWAGroups.modify_members(wa_group, phone.id, [contact.id], nil)

      assert Repo.get_by(ContactWAGroup, %{wa_group_id: wa_group.id, contact_id: contact.id})
    end

    test "removes a member when only a remove id is given", %{
      wa_group: wa_group,
      wa_managed_phone: phone,
      organization_id: org_id
    } do
      mock_success()
      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      {:ok, _} =
        ContactWAGroups.create_contact_wa_group(%{
          contact_id: contact.id,
          wa_group_id: wa_group.id,
          organization_id: org_id
        })

      assert {:ok, %{added: 0, removed: 1}} =
               ContactWAGroups.modify_members(wa_group, phone.id, [], contact.id)

      refute Repo.get_by(ContactWAGroup, %{wa_group_id: wa_group.id, contact_id: contact.id})
    end

    test "returns an error when the acting phone is not found", %{
      wa_group: wa_group,
      organization_id: org_id
    } do
      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      assert {:error, "Acting phone not found in this organization"} =
               ContactWAGroups.modify_members(wa_group, 0, [contact.id], nil)
    end

    test "propagates the error when adding members fails on Maytapi", %{
      wa_group: wa_group,
      wa_managed_phone: phone,
      organization_id: org_id
    } do
      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: Jason.encode!(%{"success" => false, "message" => "ADD_FAILED"})
         }}
      end)

      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      assert {:error, "ADD_FAILED"} =
               ContactWAGroups.modify_members(wa_group, phone.id, [contact.id], nil)
    end

    test "propagates the error when removing a member fails on Maytapi", %{
      wa_group: wa_group,
      wa_managed_phone: phone,
      organization_id: org_id
    } do
      # add succeeds, remove fails — exercises the remove-failure branch
      Tesla.Mock.mock(fn %{method: :post, url: url} ->
        body =
          if String.contains?(url, "group/remove"),
            do: %{"success" => false, "message" => "REMOVE_FAILED"},
            else: %{"success" => true}

        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(body)}}
      end)

      to_add = Fixtures.contact_fixture(%{organization_id: org_id})
      to_remove = Fixtures.contact_fixture(%{organization_id: org_id})

      {:ok, _} =
        ContactWAGroups.create_contact_wa_group(%{
          contact_id: to_remove.id,
          wa_group_id: wa_group.id,
          organization_id: org_id
        })

      assert {:error, "REMOVE_FAILED"} =
               ContactWAGroups.modify_members(wa_group, phone.id, [to_add.id], to_remove.id)
    end
  end
end
