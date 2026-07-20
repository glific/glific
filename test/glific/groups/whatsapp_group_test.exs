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
    Seeds.SeedsDev,
    WAGroup.WAManagedPhone
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

  defp mock_maytapi(groups_body) do
    Tesla.Mock.mock(fn
      %{url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/listPhones"} ->
        %Tesla.Env{
          status: 200,
          body:
            ~s([{"id":242,"number":"9829627508","status":"active","type":"whatsapp","name":""}])
        }

      _env ->
        %Tesla.Env{status: 200, body: groups_body}
    end)
  end

  test "sync_wa_groups/1 syncs groups using Maytapi API", attrs do
    mock_maytapi(
      ~s({"count":79,"data":[{"admins":["917834811115@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363213149844251@g.us","name":"Expenses","participants":["917834811116@c.us","917834811115@c.us","917834811114@c.us"]},{"admins":["917834811114@c.us","917834811115@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363203450035277@g.us","name":"Movie Plan","participants":["917834811116@c.us","917834811115@c.us","917834811114@c.us"]},{"admins":["917834811114@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363218884368888@g.us","name":"Developer Group","participants":["917834811114@c.us"]}],"limit":500,"success":true,"total":79})
    )

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
    mock_maytapi(
      ~s({"count":79,"data":[{"admins":["917834811115@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363213149844251@g.us","name":"Expenses","participants":["917834811116@c.us","917834811115@c.us","917834811114@c.us"]},{"admins":["917834811114@c.us","917834811115@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363203450035277@g.us","name":"Movie Plan","participants":["917834811116@c.us","917834811115@c.us","917834811114@c.us"]},{"admins":["917834811114@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363218884368889@g.us","name":"Movie PlanB","participants":["917834811116@c.us","917834811115@c.us","917834811114@c.us"]},{"admins":["917834811114@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363218884368888@g.us", "name":"Developer Group","participants":["917834811114@c.us"]}],"limit":500,"success":true,"total":79})
    )

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
    mock_maytapi(
      ~s({"count":79,"data":[{"admins":["917834811115@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363213149844251@g.us","name":"marketing","participants":["917834811116@c.us","917834811115@c.us","917834811114@c.us"]},{"admins":["917834811114@c.us","917834811115@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363203450035277@g.us","name":"admin group","participants":["917834811116@c.us","917834811115@c.us","917834811114@c.us"]},{"admins":["917834811114@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363218884368888@g.us","name":"","participants":["917834811114@c.us"]}],"limit":500,"success":true,"total":79})
    )

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
      group =
        group_detail(ctx.wa_group, ctx.wa_managed_phone, ["#{ctx.wa_managed_phone.phone}@c.us"])

      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)

      row = membership(ctx.wa_group.id, ctx.wa_managed_phone.id)
      assert row.is_active == true
    end

    test "deactivates memberships for groups no longer returned", ctx do
      group =
        group_detail(ctx.wa_group, ctx.wa_managed_phone, ["#{ctx.wa_managed_phone.phone}@c.us"])

      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == true

      # Phone no longer reports being in any group
      :ok = WAGroups.sync_wa_group_phones([], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == false
    end

    test "reactivates a previously inactive membership", ctx do
      group =
        group_detail(ctx.wa_group, ctx.wa_managed_phone, ["#{ctx.wa_managed_phone.phone}@c.us"])

      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)
      :ok = WAGroups.sync_wa_group_phones([], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == false

      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == true
    end

    test "skips when Maytapi returns a bsp_id that has no matching wa_group row",
         ctx do
      orphan =
        group_detail(
          %{ctx.wa_group | bsp_id: "120363099999999999@g.us"},
          ctx.wa_managed_phone,
          ["#{ctx.wa_managed_phone.phone}@c.us"]
        )

      known =
        group_detail(ctx.wa_group, ctx.wa_managed_phone, ["#{ctx.wa_managed_phone.phone}@c.us"])

      :ok = WAGroups.sync_wa_group_phones([orphan, known], ctx.wa_managed_phone)

      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_active == true
    end

    test "never changes is_primary", ctx do
      # `maybe_create_group/1` in the describe setup already inserted a
      # primary membership for our managed phone (first creator =
      # is_primary: true), so we just verify sync never disturbs it.
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_primary == true

      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, [])
      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)
      assert membership(ctx.wa_group.id, ctx.wa_managed_phone.id).is_primary == true

      # Even when the membership gets deactivated, is_primary is preserved.
      :ok = WAGroups.sync_wa_group_phones([], ctx.wa_managed_phone)
      deactivated = membership(ctx.wa_group.id, ctx.wa_managed_phone.id)
      assert deactivated.is_active == false
      assert deactivated.is_primary == true
    end

    test "cross-phone: deactivates other managed phone's row when it's not in participants",
         ctx do
      # Bug the user saw: phone M was removed from the group but M's own
      # sync is stale, so M's row stayed is_active: true. The syncing
      # phone's `participants` list is the source of truth — if M's
      # number isn't there, flip M's row inactive without waiting for M.
      {:ok, removed_contact} =
        Glific.Contacts.maybe_create_contact(%{
          phone: "919999900042",
          organization_id: ctx.organization_id,
          contact_type: "WA"
        })

      {:ok, removed_phone} =
        Glific.WAManagedPhones.create_wa_managed_phone(%{
          label: "removed",
          phone: "919999900042",
          phone_id: 4_242_424,
          status: "active",
          organization_id: ctx.organization_id,
          contact_id: removed_contact.id
        })

      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: ctx.wa_group.id,
        wa_managed_phone_id: removed_phone.id,
        organization_id: ctx.organization_id,
        is_primary: false,
        is_active: true
      })

      # ctx.wa_managed_phone syncs and sees ctx.wa_group with participants
      # that do NOT include removed_phone.phone.
      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, ["918888888888@c.us"])
      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)

      assert membership(ctx.wa_group.id, removed_phone.id).is_active == false
    end

    test "cross-phone: reactivates other managed phone's row when it IS in participants", ctx do
      # Inverse: M was previously removed (is_active: false). M is added
      # back to the group on WhatsApp. P's sync sees G with M in
      # participants → reactivate M's row without waiting for M's own sync.
      {:ok, rejoin_contact} =
        Glific.Contacts.maybe_create_contact(%{
          phone: "919999900043",
          organization_id: ctx.organization_id,
          contact_type: "WA"
        })

      {:ok, rejoin_phone} =
        Glific.WAManagedPhones.create_wa_managed_phone(%{
          label: "rejoin",
          phone: "919999900043",
          phone_id: 4_343_434,
          status: "active",
          organization_id: ctx.organization_id,
          contact_id: rejoin_contact.id
        })

      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: ctx.wa_group.id,
        wa_managed_phone_id: rejoin_phone.id,
        organization_id: ctx.organization_id,
        is_primary: false,
        is_active: false
      })

      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, ["#{rejoin_phone.phone}@c.us"])
      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)

      assert membership(ctx.wa_group.id, rejoin_phone.id).is_active == true
    end

    test "cross-phone: non-managed contact participants don't get wa_groups_phones rows", ctx do
      # Random contact phones in `participants` who aren't any of our
      # managed phones must be ignored — reconciliation iterates only the
      # org's managed phones, never the broader participants list.
      group = group_detail(ctx.wa_group, ctx.wa_managed_phone, ["917777777777@c.us"])

      :ok = WAGroups.sync_wa_group_phones([group], ctx.wa_managed_phone)

      # Only one row in wa_groups_phones for ctx.wa_group — the syncing
      # phone's. No row was created for "917777777777".
      count =
        Glific.Repo.aggregate(
          from(wgp in WAGroupPhone, where: wgp.wa_group_id == ^ctx.wa_group.id),
          :count
        )

      assert count == 1
    end
  end

  describe "maybe_create_group/1 (cross-phone)" do
    test "returns the existing group when a different phone queries it (no duplicate WAGroup row)",
         attrs do
      first_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      {:ok, original} =
        WAGroups.maybe_create_group(%{
          label: "Shared Group",
          bsp_id: "120363255555555555@g.us",
          organization_id: attrs.organization_id,
          wa_managed_phone_id: first_phone.id
        })

      # A second managed phone joins the org and now sees the same group.
      {:ok, second_contact} =
        Glific.Contacts.maybe_create_contact(%{
          phone: "919999900050",
          organization_id: attrs.organization_id,
          contact_type: "WA"
        })

      {:ok, second_phone} =
        Glific.WAManagedPhones.create_wa_managed_phone(%{
          label: "second",
          phone: "919999900050",
          phone_id: 5_555_555,
          status: "active",
          organization_id: attrs.organization_id,
          contact_id: second_contact.id
        })

      assert {:ok, found} =
               WAGroups.maybe_create_group(%{
                 label: original.label,
                 bsp_id: original.bsp_id,
                 organization_id: attrs.organization_id,
                 wa_managed_phone_id: second_phone.id
               })

      assert found.id == original.id

      rows =
        WAGroup
        |> where([wg], wg.bsp_id == ^original.bsp_id)
        |> Repo.all()

      assert length(rows) == 1, "no duplicate WAGroup row should be created"
    end
  end

  describe "primary_phone/1 and set_primary_phone/2" do
    setup attrs do
      first_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      # Default fixture status is "loading"; force "active" so the no-op
      # path doesn't pick up a status warning.
      {:ok, first_phone} =
        first_phone
        |> WAManagedPhone.changeset(%{status: "active"})
        |> Repo.update()

      {:ok, second_contact} =
        Glific.Contacts.maybe_create_contact(%{
          phone: "919999900001",
          organization_id: attrs.organization_id,
          contact_type: "WA"
        })

      {:ok, second_phone} =
        Glific.WAManagedPhones.create_wa_managed_phone(%{
          label: "second",
          phone: "919999900001",
          phone_id: 9_999_001,
          status: "active",
          organization_id: attrs.organization_id,
          contact_id: second_contact.id
        })

      {:ok, wa_group} =
        WAGroups.maybe_create_group(%{
          label: "Primary Switch Group",
          bsp_id: "120363211111111111@g.us",
          organization_id: attrs.organization_id,
          wa_managed_phone_id: first_phone.id
        })

      # maybe_create_group/1 above already inserted the first_phone
      # membership as is_primary: true. Only seed the second_phone here.
      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: wa_group.id,
        wa_managed_phone_id: second_phone.id,
        organization_id: attrs.organization_id,
        is_primary: false,
        is_active: true
      })

      Map.merge(attrs, %{
        first_phone: first_phone,
        second_phone: second_phone,
        wa_group: wa_group
      })
    end

    test "primary_phone/1 returns the WAManagedPhone whose membership is is_primary + is_active",
         ctx do
      assert phone = WAGroups.primary_phone(ctx.wa_group.id)
      assert phone.id == ctx.first_phone.id
    end

    test "primary_phone/1 returns nil when no membership is primary", ctx do
      # Demote the existing primary so no row is is_primary: true.
      ctx.wa_group.id
      |> membership(ctx.first_phone.id)
      |> WAGroupPhone.changeset(%{is_primary: false})
      |> Repo.update!()

      assert WAGroups.primary_phone(ctx.wa_group.id) == nil
    end

    test "primary_phone/1 returns nil when the primary membership is inactive", ctx do
      ctx.wa_group.id
      |> membership(ctx.first_phone.id)
      |> WAGroupPhone.changeset(%{is_active: false})
      |> Repo.update!()

      assert WAGroups.primary_phone(ctx.wa_group.id) == nil
    end

    test "set_primary_phone/2 demotes the current primary and promotes the target", ctx do
      assert {:ok, %{primary_phone: promoted, warning: nil}} =
               WAGroups.set_primary_phone(ctx.wa_group.id, ctx.second_phone.id)

      assert promoted.wa_managed_phone_id == ctx.second_phone.id
      assert promoted.is_primary == true

      old_primary = membership(ctx.wa_group.id, ctx.first_phone.id)
      assert old_primary.is_primary == false

      # Exactly one row remains is_primary: true for this group.
      assert WAGroups.primary_phone(ctx.wa_group.id).id == ctx.second_phone.id
    end

    test "set_primary_phone/2 returns :membership_not_found when no row exists", ctx do
      {:ok, ghost_contact} =
        Glific.Contacts.maybe_create_contact(%{
          phone: "919999900099",
          organization_id: ctx.organization_id,
          contact_type: "WA"
        })

      {:ok, ghost_phone} =
        Glific.WAManagedPhones.create_wa_managed_phone(%{
          label: "ghost",
          phone: "919999900099",
          phone_id: 9_999_099,
          status: "active",
          organization_id: ctx.organization_id,
          contact_id: ghost_contact.id
        })

      assert {:error, :membership_not_found} =
               WAGroups.set_primary_phone(ctx.wa_group.id, ghost_phone.id)
    end

    test "set_primary_phone/2 returns :inactive_membership when target is is_active: false",
         ctx do
      ctx.wa_group.id
      |> membership(ctx.second_phone.id)
      |> WAGroupPhone.changeset(%{is_active: false})
      |> Repo.update!()

      assert {:error, :inactive_membership} =
               WAGroups.set_primary_phone(ctx.wa_group.id, ctx.second_phone.id)

      # Original primary unchanged.
      assert WAGroups.primary_phone(ctx.wa_group.id).id == ctx.first_phone.id
    end

    test "set_primary_phone/2 is a no-op when the target is already the primary", ctx do
      # No demote+promote should fire — the row stays at is_primary: true.
      original = membership(ctx.wa_group.id, ctx.first_phone.id)

      assert {:ok, %{primary_phone: returned, warning: nil}} =
               WAGroups.set_primary_phone(ctx.wa_group.id, ctx.first_phone.id)

      assert returned.id == original.id
      assert returned.is_primary == true

      # DB state unchanged: original primary still primary, runner-up still not.
      assert membership(ctx.wa_group.id, ctx.first_phone.id).is_primary == true
      assert membership(ctx.wa_group.id, ctx.second_phone.id).is_primary == false
    end

    test "set_primary_phone/2 succeeds and surfaces a warning when target phone's Maytapi status is not 'active'",
         ctx do
      ctx.second_phone
      |> WAManagedPhone.changeset(%{status: "loading"})
      |> Repo.update!()

      assert {:ok, %{primary_phone: promoted, warning: warning}} =
               WAGroups.set_primary_phone(ctx.wa_group.id, ctx.second_phone.id)

      assert promoted.is_primary == true
      assert WAGroups.primary_phone(ctx.wa_group.id).id == ctx.second_phone.id

      assert is_binary(warning)
      assert warning =~ "'loading'"
      assert warning =~ ctx.second_phone.phone
    end

    test "next_active_member/2 returns the oldest active member (eligible by both wgp.is_active and Maytapi status)",
         ctx do
      # Setup has first_phone (primary, active) and second_phone (active).
      # Excluding first_phone should give us second_phone.
      assert phone = WAGroups.next_active_member(ctx.wa_group.id, [ctx.first_phone.id])
      assert phone.id == ctx.second_phone.id
    end

    test "next_active_member/2 skips members whose wa_groups_phones.is_active is false", ctx do
      ctx.wa_group.id
      |> membership(ctx.second_phone.id)
      |> WAGroupPhone.changeset(%{is_active: false})
      |> Repo.update!()

      assert WAGroups.next_active_member(ctx.wa_group.id, [ctx.first_phone.id]) == nil
    end

    test "next_active_member/2 skips members whose Maytapi status isn't 'active'", ctx do
      ctx.second_phone
      |> WAManagedPhone.changeset(%{status: "loading"})
      |> Repo.update!()

      assert WAGroups.next_active_member(ctx.wa_group.id, [ctx.first_phone.id]) == nil
    end

    test "next_active_member/2 with no exclude returns the primary itself if it qualifies", ctx do
      assert phone = WAGroups.next_active_member(ctx.wa_group.id)
      assert phone.id == ctx.first_phone.id
    end

    test "next_active_member/2 returns nil when the group has no eligible members", ctx do
      assert WAGroups.next_active_member(ctx.wa_group.id, [
               ctx.first_phone.id,
               ctx.second_phone.id
             ]) ==
               nil
    end
  end
end
