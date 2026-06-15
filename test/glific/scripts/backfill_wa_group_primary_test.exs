defmodule Glific.Scripts.BackfillWAGroupPrimaryTest do
  use Glific.DataCase, async: false

  alias Glific.{
    Fixtures,
    Groups.WAGroupPhone,
    Repo,
    Scripts.BackfillWAGroupPrimary
  }

  describe "run/1" do
    test "promotes the legacy phone when it has an active membership (Case A)",
         %{organization_id: org_id} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: wa_group.id,
        wa_managed_phone_id: phone.id,
        organization_id: org_id,
        is_primary: false,
        is_active: true
      })

      assert %{
               org_id: ^org_id,
               groups_examined: 1,
               fixed_via_legacy: 1,
               unfixable: 0
             } = BackfillWAGroupPrimary.run(org_id)

      primary = Repo.get_by(WAGroupPhone, %{wa_group_id: wa_group.id, is_primary: true})
      assert primary.wa_managed_phone_id == phone.id
      assert primary.is_active == true
    end

    test "skips groups whose legacy phone has no active membership",
         %{organization_id: org_id} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: wa_group.id,
        wa_managed_phone_id: phone.id,
        organization_id: org_id,
        is_primary: false,
        is_active: false
      })

      assert %{groups_examined: 1, fixed_via_legacy: 0, unfixable: 1} =
               BackfillWAGroupPrimary.run(org_id)

      refute Repo.get_by(WAGroupPhone, %{wa_group_id: wa_group.id, is_primary: true})
    end

    test "is idempotent: re-running over a group that already has a primary is a no-op",
         %{organization_id: org_id} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      _wa_group =
        Fixtures.wa_group_with_primary_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      assert %{groups_examined: 0, fixed_via_legacy: 0, unfixable: 0} =
               BackfillWAGroupPrimary.run(org_id)
    end

    test "ignores groups with zero membership rows (filtered by inner join)",
         %{organization_id: org_id} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      _wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      assert %{groups_examined: 0, fixed_via_legacy: 0, unfixable: 0} =
               BackfillWAGroupPrimary.run(org_id)
    end

    test "mixed batch: fixable, unfixable, and already-fixed groups counted separately",
         %{organization_id: org_id} do
      phone_a = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      fixable =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone_a.id,
          bsp_id: "120363111@g.us"
        })

      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: fixable.id,
        wa_managed_phone_id: phone_a.id,
        organization_id: org_id,
        is_primary: false,
        is_active: true
      })

      unfixable =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone_a.id,
          bsp_id: "120363222@g.us",
          label: "second"
        })

      Fixtures.wa_group_phone_fixture(%{
        wa_group_id: unfixable.id,
        wa_managed_phone_id: phone_a.id,
        organization_id: org_id,
        is_primary: false,
        is_active: false
      })

      _already_fixed =
        Fixtures.wa_group_with_primary_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone_a.id,
          bsp_id: "120363333@g.us",
          label: "third"
        })

      assert %{groups_examined: 2, fixed_via_legacy: 1, unfixable: 1} =
               BackfillWAGroupPrimary.run(org_id)

      assert Repo.get_by(WAGroupPhone, %{wa_group_id: fixable.id, is_primary: true})
      refute Repo.get_by(WAGroupPhone, %{wa_group_id: unfixable.id, is_primary: true})
    end
  end

  describe "run_all/0" do
    test "returns one result per organization" do
      results = BackfillWAGroupPrimary.run_all()

      assert is_list(results)
      assert length(results) >= 1

      Enum.each(results, fn r ->
        assert %{org_id: _, groups_examined: _, fixed_via_legacy: _, unfixable: _} = r
      end)
    end
  end
end
