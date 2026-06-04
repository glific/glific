defmodule Glific.Groups.WAGroupsTest do
  use Glific.DataCase, async: false
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Groups.WAGroups,
    Partners,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    Fixtures.wa_managed_phone_fixture(%{organization_id: organization.id})

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

    :ok
  end

  test "sync_wa_groups/1 syncs groups using Maytapi API", attrs do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\"count\":79,\"data\":[{\"admins\":[\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363213149844251@g.us\",\"name\":\"Expenses\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\",\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363203450035277@g.us\",\"name\":\"Movie Plan\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368888@g.us\",\"name\":\"Developer Group\",\"participants\":[\"917834811114@c.us\"]}],\"limit\":500,\"success\":true,\"total\":79}"
      }
    end)

    assert :ok == WAGroups.sync_wa_groups(attrs.organization_id)

    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Expenses"})
    assert group.label == "Expenses"
    assert group.bsp_id == "120363213149844251@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Movie Plan"})
    assert group.label == "Movie Plan"
    assert group.bsp_id == "120363203450035277@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Developer Group"})
    assert group.label == "Developer Group"
    assert group.bsp_id == "120363218884368888@g.us"

    # when we try to enter redundant groups again.
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\"count\":79,\"data\":[{\"admins\":[\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363213149844251@g.us\",\"name\":\"Expenses\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\",\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363203450035277@g.us\",\"name\":\"Movie Plan\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368889@g.us\",\"name\":\"Movie PlanB\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368888@g.us\", \"name\":\"Developer Group\",\"participants\":[\"917834811114@c.us\"]}],\"limit\":500,\"success\":true,\"total\":79}"
      }
    end)

    assert :ok == WAGroups.sync_wa_groups(attrs.organization_id)
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Expenses"})
    assert group.label == "Expenses"
    assert group.bsp_id == "120363213149844251@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Movie Plan"})
    assert group.label == "Movie Plan"
    assert group.bsp_id == "120363203450035277@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Developer Group"})
    assert group.label == "Developer Group"
    assert group.bsp_id == "120363218884368888@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Movie PlanB"})
    assert group.label == "Movie PlanB"
    assert group.bsp_id == "120363218884368889@g.us"
  end

  test "setting maytapi webhook endpoint, success", attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "pid" => "dc01968f-####-####-####-7cfcf51aa423",
            "webhook" => "https://myserver.com/send/callback/here",
            "ack_delivery" => true,
            "phone_limit" => 2
          }
        }
    end)

    assert :ok =
             WAGroups.set_webhook_endpoint(%{
               id: attrs.organization_id,
               shortcode: "maytapi"
             })
  end

  test "setting maytapi webhook endpoint, failed", attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{
            "message" => "error"
          }
        }
    end)

    assert {:error, _} =
             WAGroups.set_webhook_endpoint(%{
               id: attrs.organization_id,
               shortcode: "maytapi"
             })
  end

  test "sync_wa_groups/1 syncs groups for empty group label", attrs do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\"count\":79,\"data\":[{\"admins\":[\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363213149844251@g.us\",\"name\":\"marketing\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\",\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363203450035277@g.us\",\"name\":\"admin group\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368888@g.us\",\"name\":\"\",\"participants\":[\"917834811114@c.us\"]}],\"limit\":500,\"success\":true,\"total\":79}"
      }
    end)

    assert :ok == WAGroups.sync_wa_groups(attrs.organization_id)

    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "marketing"})
    assert group.label == "marketing"
    assert group.bsp_id == "120363213149844251@g.us"

    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "admin group"})
    assert group.label == "admin group"
    assert group.bsp_id == "120363203450035277@g.us"

    # group with an empty name is not created
    assert is_nil(Repo.get_by(WAGroup, label: ""))
  end

  describe "maybe_create_group/1" do
    test "creates a new group when it doesn't exist", attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      params = %{
        label: "New Group",
        bsp_id: "120363299999999999@g.us",
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      }

      assert {:ok, wa_group} = WAGroups.maybe_create_group(params)
      assert wa_group.label == "New Group"
      assert wa_group.bsp_id == "120363299999999999@g.us"
    end

    test "returns existing group when label matches", attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      params = %{
        label: "Existing Group",
        bsp_id: "120363288888888888@g.us",
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      }

      {:ok, original} = WAGroups.maybe_create_group(params)
      {:ok, found} = WAGroups.maybe_create_group(params)

      assert original.id == found.id
      assert found.label == "Existing Group"
    end

    test "updates label when existing group has a different label", attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      params = %{
        label: "Old Label",
        bsp_id: "120363277777777777@g.us",
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      }

      {:ok, original} = WAGroups.maybe_create_group(params)
      assert original.label == "Old Label"

      updated_params = %{params | label: "New Label"}
      {:ok, updated} = WAGroups.maybe_create_group(updated_params)

      assert updated.id == original.id
      assert updated.label == "New Label"
    end

    test "returns existing group without updating when label is nil", attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      params = %{
        label: "Keep This Label",
        bsp_id: "120363266666666666@g.us",
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      }

      {:ok, original} = WAGroups.maybe_create_group(params)
      assert original.label == "Keep This Label"

      nil_label_params = %{params | label: nil}
      {:ok, result} = WAGroups.maybe_create_group(nil_label_params)

      assert result.id == original.id
      assert result.label == "Keep This Label"
    end
  end

  describe "sync_wa_groups_with_contacts/2 (non-destructive diff)" do
    setup attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      {:ok, wa_group} =
        WAGroups.maybe_create_group(%{
          label: "Diff Group",
          bsp_id: "120363111111111111@g.us",
          organization_id: attrs.organization_id,
          wa_managed_phone_id: wa_managed_phone.id
        })

      Map.merge(attrs, %{wa_managed_phone: wa_managed_phone, wa_group: wa_group})
    end

    defp group_detail(wa_group, wa_managed_phone, participants, admins \\ []) do
      %{
        name: wa_group.label,
        bsp_id: wa_group.bsp_id,
        wa_managed_phone_id: wa_managed_phone.id,
        participants: participants,
        admins: admins
      }
    end

    defp member_contact_ids(wa_group_id) do
      ContactWAGroups.list_contact_wa_group(%{wa_group_id: wa_group_id})
      |> Enum.map(& &1.contact_id)
      |> Enum.sort()
    end

    test "adds new participants and sets admin flag", ctx do
      first_group =
        group_detail(
          ctx.wa_group,
          ctx.wa_managed_phone,
          ["918000000001@c.us", "918000000002@c.us"],
          ["918000000001@c.us"]
        )

      :ok = WAGroups.sync_wa_groups_with_contacts([first_group], ctx.organization_id)

      members = ContactWAGroups.list_contact_wa_group(%{wa_group_id: ctx.wa_group.id})
      assert length(members) == 2

      second_group =
        group_detail(
          ctx.wa_group,
          ctx.wa_managed_phone,
          ["918000000003@c.us", "918000000002@c.us"],
          ["918000000003@c.us"]
        )

      :ok = WAGroups.sync_wa_groups_with_contacts([second_group], ctx.organization_id)

      members = ContactWAGroups.list_contact_wa_group(%{wa_group_id: ctx.wa_group.id})
      assert length(members) == 2
      admin_member = Enum.find(members, & &1.is_admin)
      admin_contact = Glific.Contacts.get_contact!(admin_member.contact_id)
      assert admin_contact.phone == "918000000003"
    end

    test "removes departed participants", ctx do
      first =
        group_detail(ctx.wa_group, ctx.wa_managed_phone, [
          "918000000001@c.us",
          "918000000002@c.us"
        ])

      :ok = WAGroups.sync_wa_groups_with_contacts([first], ctx.organization_id)
      assert length(member_contact_ids(ctx.wa_group.id)) == 2

      # Second sync drops 918000000002
      second = group_detail(ctx.wa_group, ctx.wa_managed_phone, ["918000000001@c.us"])
      :ok = WAGroups.sync_wa_groups_with_contacts([second], ctx.organization_id)

      remaining = member_contact_ids(ctx.wa_group.id)
      assert length(remaining) == 1

      kept = Glific.Contacts.get_contact!(hd(remaining))
      assert kept.phone == "918000000001"
    end

    test "reconciles is_admin for retained members (promote/demote)", ctx do
      # Initial: 918000000001 is admin, 918000000002 is regular member
      first =
        group_detail(
          ctx.wa_group,
          ctx.wa_managed_phone,
          ["918000000001@c.us", "918000000002@c.us"],
          ["918000000001@c.us"]
        )

      :ok = WAGroups.sync_wa_groups_with_contacts([first], ctx.organization_id)

      # Flip admin status: demote ..0001, promote ..0002
      second =
        group_detail(
          ctx.wa_group,
          ctx.wa_managed_phone,
          ["918000000001@c.us", "918000000002@c.us"],
          ["918000000002@c.us"]
        )

      :ok = WAGroups.sync_wa_groups_with_contacts([second], ctx.organization_id)

      rows =
        ContactWAGroup
        |> where([c], c.wa_group_id == ^ctx.wa_group.id)
        |> Repo.all()

      assert length(rows) == 2

      admin_phones =
        rows
        |> Enum.filter(& &1.is_admin)
        |> Enum.map(&Glific.Contacts.get_contact!(&1.contact_id).phone)

      assert admin_phones == ["918000000002"]
    end

    test "retained member with unchanged admin status is not touched (no updated_at bump)", ctx do
      group =
        group_detail(
          ctx.wa_group,
          ctx.wa_managed_phone,
          ["918000000001@c.us"],
          ["918000000001@c.us"]
        )

      :ok = WAGroups.sync_wa_groups_with_contacts([group], ctx.organization_id)
      [member] = ContactWAGroups.list_contact_wa_group(%{wa_group_id: ctx.wa_group.id})

      past = ~U[2020-01-01 00:00:00Z]

      {1, _} =
        ContactWAGroup
        |> where([c], c.id == ^member.id)
        |> Repo.update_all(set: [updated_at: past])

      # Re-sync with the same admin status — row should stay frozen.
      :ok = WAGroups.sync_wa_groups_with_contacts([group], ctx.organization_id)

      reloaded = Repo.get!(ContactWAGroup, member.id)
      assert reloaded.is_admin == true
      assert DateTime.compare(reloaded.updated_at, past) == :eq
    end

    test "unchanged participants are not touched (no updated_at bump)", ctx do
      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, ["918000000001@c.us"])
      :ok = WAGroups.sync_wa_groups_with_contacts([group], ctx.organization_id)

      [member] = ContactWAGroups.list_contact_wa_group(%{wa_group_id: ctx.wa_group.id})

      # Backdate updated_at, then prove a re-sync with the same participant
      # leaves the row completely untouched.
      past = ~U[2020-01-01 00:00:00Z]

      {1, _} =
        ContactWAGroup
        |> where([c], c.id == ^member.id)
        |> Repo.update_all(set: [updated_at: past])

      :ok = WAGroups.sync_wa_groups_with_contacts([group], ctx.organization_id)

      reloaded = Repo.get!(ContactWAGroup, member.id)
      assert DateTime.compare(reloaded.updated_at, past) == :eq
    end
  end

  describe "sync_wa_group_phones/2" do
    setup attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      {:ok, wa_group} =
        WAGroups.maybe_create_group(%{
          label: "Membership Group",
          bsp_id: "120363222222222222@g.us",
          organization_id: attrs.organization_id,
          wa_managed_phone_id: wa_managed_phone.id
        })

      Map.merge(attrs, %{wa_managed_phone: wa_managed_phone, wa_group: wa_group})
    end

    defp membership(wa_group_id, wa_managed_phone_id) do
      Repo.get_by(WAGroupPhone, %{
        wa_group_id: wa_group_id,
        wa_managed_phone_id: wa_managed_phone_id
      })
    end

    test "upserts an active membership for groups the phone is in", ctx do
      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, [])

      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)

      row = membership(ctx.wa_group.id, ctx.wa_managed_phone.id)
      assert row.is_active == true
    end

    test "deactivates memberships for groups no longer returned", ctx do
      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, [])
      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == true

      # Phone no longer reports being in any group
      :ok = WAGroups.sync_wa_group_phones([], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == false
    end

    test "reactivates a previously inactive membership", ctx do
      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, [])
      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)
      :ok = WAGroups.sync_wa_group_phones([], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == false

      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == true
    end

    test "never changes is_primary", ctx do
      # Seed a primary membership (as Phase 1 backfill would).
      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: ctx.wa_group.id,
        wa_managed_phone_id: ctx.wa_managed_phone.id,
        organization_id: ctx.organization_id,
        is_primary: true,
        is_active: true
      })

      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, [])
      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_primary == true

      # Even when the membership gets deactivated, is_primary is preserved.
      :ok = WAGroups.sync_wa_group_phones([], ctx.wa_managed_phone)
      deactivated = membership(ctx.wa_group.id, ctx.wa_managed_phone.id)
      assert deactivated.is_active == false
      assert deactivated.is_primary == true
    end
  end
end
