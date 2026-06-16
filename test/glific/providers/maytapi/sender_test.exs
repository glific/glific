defmodule Glific.Providers.Maytapi.SenderTest do
  use Glific.DataCase, async: false

  import Ecto.Query

  alias Glific.{
    Fixtures,
    Groups.WAGroupPhone,
    Groups.WAGroups,
    Notifications.Notification,
    Providers.Maytapi.Sender,
    Repo,
    Seeds.SeedsDev,
    WAGroup.WAManagedPhone
  }

  setup do
    organization = SeedsDev.seed_organizations()
    # Primary phone (forced active; default fixture status is "loading").
    first_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: organization.id})
      |> WAManagedPhone.changeset(%{status: "active"})
      |> Repo.update!()

    {:ok, second_contact} =
      Glific.Contacts.maybe_create_contact(%{
        phone: "919999900001",
        organization_id: organization.id,
        contact_type: "WA"
      })

    {:ok, second_phone} =
      Glific.WAManagedPhones.create_wa_managed_phone(%{
        label: "second",
        phone: "919999900001",
        phone_id: 9_999_001,
        status: "active",
        organization_id: organization.id,
        contact_id: second_contact.id
      })

    # Group created with first_phone; maybe_create_group inserts the primary
    # membership automatically. Seed second_phone as a non-primary active member.
    {:ok, wa_group} =
      WAGroups.maybe_create_group(%{
        label: "Sender Group",
        bsp_id: "120363222222222222@g.us",
        organization_id: organization.id,
        wa_managed_phone_id: first_phone.id
      })

    Fixtures.wa_group_phone_fixture(%{
      wa_group_id: wa_group.id,
      wa_managed_phone_id: second_phone.id,
      organization_id: organization.id,
      is_primary: false,
      is_active: true
    })

    {:ok,
     %{
       organization_id: organization.id,
       first_phone: first_phone,
       second_phone: second_phone,
       wa_group: wa_group
     }}
  end

  describe "pick_for_send/2" do
    test "returns primary with :primary tag when primary is healthy", ctx do
      assert {:ok, phone, :primary} = Sender.pick_for_send(ctx.wa_group)
      assert phone.id == ctx.first_phone.id

      # Memberships untouched.
      assert membership(ctx.wa_group.id, ctx.first_phone.id).is_primary == true
      assert membership(ctx.wa_group.id, ctx.second_phone.id).is_primary == false
    end

    test "fails over and promotes when primary's Maytapi status isn't 'active'", ctx do
      ctx.first_phone
      |> WAManagedPhone.changeset(%{status: "loading"})
      |> Repo.update!()

      assert {:ok, phone, :failover} = Sender.pick_for_send(ctx.wa_group)
      assert phone.id == ctx.second_phone.id

      # Promotion happened.
      assert WAGroups.primary_phone(ctx.wa_group.id).id == ctx.second_phone.id
      assert membership(ctx.wa_group.id, ctx.first_phone.id).is_primary == false

      # Warning notification fired.
      assert warning_notification_exists?(ctx, "switched to phone #{ctx.second_phone.phone}")
    end

    test "fails over when primary is in opts[:exclude] (response-handler retry path)", ctx do
      assert {:ok, phone, :failover} =
               Sender.pick_for_send(ctx.wa_group,
                 exclude: [ctx.first_phone.id],
                 reason: :send_error
               )

      assert phone.id == ctx.second_phone.id
      assert WAGroups.primary_phone(ctx.wa_group.id).id == ctx.second_phone.id
    end

    test "relaxed failover: when no Maytapi-active member exists, the oldest group member (including the unhealthy primary) is used",
         ctx do
      ctx.first_phone |> WAManagedPhone.changeset(%{status: "loading"}) |> Repo.update!()
      ctx.second_phone |> WAManagedPhone.changeset(%{status: "loading"}) |> Repo.update!()

      assert {:ok, phone, :failover} = Sender.pick_for_send(ctx.wa_group)

      # first_phone is the older member (inserted by maybe_create_group during
      # setup, before second_phone's explicit fixture). Relaxed pick orders by
      # membership inserted_at ASC, so it returns first_phone — which is the
      # current primary. promote/2 is idempotent in this case.
      assert phone.id == ctx.first_phone.id
      assert WAGroups.primary_phone(ctx.wa_group.id).id == ctx.first_phone.id

      # Warning notification fired; NO critical.
      assert warning_notification_exists?(ctx, "no backup is available")
      refute critical_notification_exists?(ctx, "No active managed phones")
    end

    test "returns {:error, :no_active_phones} only when every membership is deactivated",
         ctx do
      # Deactivate both memberships — no group-active members remain.
      WAGroupPhone
      |> where([wa_group_phone], wa_group_phone.wa_group_id == ^ctx.wa_group.id)
      |> Repo.update_all(set: [is_active: false])

      assert {:error, :no_active_phones} = Sender.pick_for_send(ctx.wa_group)
      assert critical_notification_exists?(ctx, "No active managed phones")
    end

    test "single-member group: returns the only member when it's healthy", ctx do
      # Remove the second member to simulate a single-member group.
      Repo.delete!(membership(ctx.wa_group.id, ctx.second_phone.id))

      assert {:ok, phone, :primary} = Sender.pick_for_send(ctx.wa_group)
      assert phone.id == ctx.first_phone.id
    end

    test "single-member group: relaxed-promotes the only member even when unhealthy", ctx do
      Repo.delete!(membership(ctx.wa_group.id, ctx.second_phone.id))

      ctx.first_phone
      |> WAManagedPhone.changeset(%{status: "loading"})
      |> Repo.update!()

      # exclude must omit the only member; pick_for_send is called as part
      # of the normal flow (not the retry hook), so exclude is [].
      assert {:ok, phone, :failover} = Sender.pick_for_send(ctx.wa_group)
      assert phone.id == ctx.first_phone.id
    end

    test "deactivated memberships are skipped: relaxed pick falls through to the still-active primary",
         ctx do
      ctx.first_phone
      |> WAManagedPhone.changeset(%{status: "loading"})
      |> Repo.update!()

      # Deactivate second_phone's membership. first_phone (primary, status:
      # loading) remains the only group-active member, so the relaxed pick
      # returns it via the "no backup available" path.
      ctx.wa_group.id
      |> membership(ctx.second_phone.id)
      |> WAGroupPhone.changeset(%{is_active: false})
      |> Repo.update!()

      assert {:ok, phone, :failover} = Sender.pick_for_send(ctx.wa_group)
      assert phone.id == ctx.first_phone.id
    end

    test "failover with no primary membership: picks the oldest member and notifies (primary-not-set wording)",
         ctx do
      # Demote both memberships so the group has rows but no is_primary one.
      # primary_phone/1 then returns nil, exercising the nil-primary
      # failover_message clause.
      WAGroupPhone
      |> where([wa_group_phone], wa_group_phone.wa_group_id == ^ctx.wa_group.id)
      |> Repo.update_all(set: [is_primary: false])

      assert {:ok, phone, :failover} = Sender.pick_for_send(ctx.wa_group)
      assert phone.id == ctx.first_phone.id

      assert warning_notification_exists?(
               ctx,
               "Primary phone for group #{ctx.wa_group.label} is not set"
             )
    end
  end

  describe "promote/2" do
    test "delegates to WAGroups.set_primary_phone/2 and demotes the current primary", ctx do
      assert {:ok, _} = Sender.promote(ctx.wa_group.id, ctx.second_phone.id)
      assert WAGroups.primary_phone(ctx.wa_group.id).id == ctx.second_phone.id
      assert membership(ctx.wa_group.id, ctx.first_phone.id).is_primary == false
    end
  end

  defp membership(wa_group_id, wa_managed_phone_id) do
    Repo.get_by!(WAGroupPhone, %{
      wa_group_id: wa_group_id,
      wa_managed_phone_id: wa_managed_phone_id
    })
  end

  defp warning_notification_exists?(ctx, substring) do
    notification_exists?(ctx, "Warning", substring)
  end

  defp critical_notification_exists?(ctx, substring) do
    notification_exists?(ctx, "Critical", substring)
  end

  defp notification_exists?(ctx, severity, substring) do
    Notification
    |> where([n], n.organization_id == ^ctx.organization_id)
    |> Repo.all()
    |> Enum.any?(fn n -> n.severity == severity and String.contains?(n.message, substring) end)
  end
end
