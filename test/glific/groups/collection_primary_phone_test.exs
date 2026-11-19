defmodule Glific.Groups.CollectionPrimaryPhoneTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Groups,
    Groups.CollectionPrimaryPhone,
    Groups.WAGroupPhone,
    Groups.WaGroupsCollections,
    Jobs.UserJob,
    Jobs.UserJobWorker,
    Repo
  }

  setup %{organization_id: organization_id} do
    # `wa_managed_phone_fixture` leaks unknown attrs into the contact changeset,
    # so set the Maytapi status (a WAManagedPhone field) with an update.
    phone =
      %{organization_id: organization_id}
      |> Fixtures.wa_managed_phone_fixture()
      |> set_status("active")

    {:ok, collection} =
      Groups.create_group(%{label: "Broadcast collection", organization_id: organization_id})

    %{organization_id: organization_id, phone: phone, collection: collection}
  end

  defp set_status(phone, status) do
    phone |> Ecto.Changeset.change(status: status) |> Repo.update!()
  end

  # Build a WA group, add it to the collection, and (optionally) seed the phone's
  # membership row for it.
  defp group_in_collection(context, membership) do
    %{organization_id: organization_id, phone: phone, collection: collection} = context

    suffix = System.unique_integer([:positive])

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization_id,
        wa_managed_phone_id: phone.id,
        label: "Group #{suffix}",
        bsp_id: "12036#{suffix}@g.us"
      })

    {:ok, _} =
      WaGroupsCollections.create_wa_groups_collection(%{
        group_id: collection.id,
        wa_group_id: wa_group.id,
        organization_id: organization_id
      })

    case membership do
      nil ->
        :ok

      attrs ->
        Fixtures.wa_group_phone_fixture(
          Map.merge(
            %{
              wa_group_id: wa_group.id,
              wa_managed_phone_id: phone.id,
              organization_id: organization_id
            },
            attrs
          )
        )
    end

    wa_group
  end

  defp primary?(wa_group_id, wa_managed_phone_id) do
    Repo.get_by(WAGroupPhone, %{
      wa_group_id: wa_group_id,
      wa_managed_phone_id: wa_managed_phone_id
    }).is_primary
  end

  defp run(organization_id, collection, phone) do
    {:ok, %{user_job_id: user_job_id}} =
      CollectionPrimaryPhone.set_primary_phone_for_collection(
        organization_id,
        collection.id,
        phone.id
      )

    Oban.drain_queue(queue: :wa_group, with_scheduled: true)
    UserJobWorker.check_user_job_status(organization_id)
    user_job_id
  end

  describe "set_primary_phone_for_collection/3" do
    test "promotes the phone in valid groups and reports the skipped ones", context do
      %{organization_id: organization_id, phone: phone, collection: collection} = context

      to_promote = group_in_collection(context, %{is_active: true, is_primary: false})
      already_primary = group_in_collection(context, %{is_active: true, is_primary: true})
      inactive = group_in_collection(context, %{is_active: false, is_primary: false})
      not_member = group_in_collection(context, nil)

      user_job_id = run(organization_id, collection, phone)

      # promoted where valid; already-primary left untouched
      assert primary?(to_promote.id, phone.id)
      assert primary?(already_primary.id, phone.id)

      user_job = Repo.get!(UserJob, user_job_id)
      assert user_job.status == "success"

      skipped = user_job.errors["errors"]
      assert skipped["#{inactive.label} (##{inactive.id})"] == "member_inactive"
      assert skipped["#{not_member.label} (##{not_member.id})"] == "not_a_member"
      # valid + already-primary groups are not reported as skips
      assert map_size(skipped) == 2
    end

    test "skips every member group when the phone is unhealthy", context do
      %{organization_id: organization_id, phone: phone, collection: collection} = context

      unhealthy_phone = set_status(phone, "loading")
      wa_group = group_in_collection(context, %{is_active: true, is_primary: false})

      user_job_id = run(organization_id, collection, unhealthy_phone)

      refute primary?(wa_group.id, unhealthy_phone.id)

      skipped = Repo.get!(UserJob, user_job_id).errors["errors"]
      assert skipped["#{wa_group.label} (##{wa_group.id})"] == "phone_status_unhealthy"
    end

    test "returns an error (no job) when the phone is a member of no group in the collection",
         context do
      %{organization_id: organization_id, phone: phone, collection: collection} = context

      # a group in the collection, but the phone is not a member of it
      group_in_collection(context, nil)

      assert {:error, message} =
               CollectionPrimaryPhone.set_primary_phone_for_collection(
                 organization_id,
                 collection.id,
                 phone.id
               )

      assert message =~ "not a member of any WhatsApp group"
      assert UserJob.list_user_jobs(%{filter: %{organization_id: organization_id}}) == []
    end

    test "errors when the collection has no WhatsApp groups", context do
      %{organization_id: organization_id, phone: phone, collection: collection} = context

      assert {:error, "This collection has no WhatsApp groups."} =
               CollectionPrimaryPhone.set_primary_phone_for_collection(
                 organization_id,
                 collection.id,
                 phone.id
               )
    end

    test "errors when the phone does not exist", context do
      %{organization_id: organization_id, collection: collection} = context
      group_in_collection(context, %{is_active: true, is_primary: false})

      assert {:error, "The selected WhatsApp phone was not found."} =
               CollectionPrimaryPhone.set_primary_phone_for_collection(
                 organization_id,
                 collection.id,
                 0
               )
    end

    test "does not act on another organization's phone (tenant isolation)", context do
      %{organization_id: organization_id, collection: collection} = context
      group_in_collection(context, %{is_active: true, is_primary: false})

      other_org = Fixtures.organization_fixture()
      Repo.put_organization_id(other_org.id)

      other_phone =
        %{organization_id: other_org.id}
        |> Fixtures.wa_managed_phone_fixture()
        |> set_status("active")

      Repo.put_organization_id(organization_id)

      # the org-scoped lookup means org 1 can't drive another org's phone
      assert {:error, "The selected WhatsApp phone was not found."} =
               CollectionPrimaryPhone.set_primary_phone_for_collection(
                 organization_id,
                 collection.id,
                 other_phone.id
               )
    end
  end

  describe "get_report/2" do
    test "returns the skipped-groups CSV once the job is complete", context do
      %{organization_id: organization_id, phone: phone, collection: collection} = context

      group_in_collection(context, %{is_active: true, is_primary: false})
      inactive = group_in_collection(context, %{is_active: false, is_primary: false})

      user_job_id = run(organization_id, collection, phone)

      assert {:ok, %{csv_rows: csv_rows}} =
               CollectionPrimaryPhone.get_report(organization_id, %{user_job_id: user_job_id})

      assert csv_rows =~ "Group,Reason"
      assert csv_rows =~ "#{inactive.label} (##{inactive.id}),member_inactive"
    end

    test "escapes group labels containing commas in the CSV", context do
      %{organization_id: organization_id, phone: phone, collection: collection} = context

      suffix = System.unique_integer([:positive])

      comma_group =
        Fixtures.wa_group_fixture(%{
          organization_id: organization_id,
          wa_managed_phone_id: phone.id,
          label: "Delhi, Zone A",
          bsp_id: "12036#{suffix}@g.us"
        })

      {:ok, _} =
        WaGroupsCollections.create_wa_groups_collection(%{
          group_id: collection.id,
          wa_group_id: comma_group.id,
          organization_id: organization_id
        })

      # a valid member group so the job actually enqueues; comma_group has no
      # membership → skipped as not_a_member and lands in the report
      group_in_collection(context, %{is_active: true, is_primary: false})

      user_job_id = run(organization_id, collection, phone)

      assert {:ok, %{csv_rows: csv_rows}} =
               CollectionPrimaryPhone.get_report(organization_id, %{user_job_id: user_job_id})

      # the comma-containing label is quoted, so the row keeps exactly two columns
      assert csv_rows =~ "\"Delhi, Zone A (##{comma_group.id})\",not_a_member"
    end

    test "reports in-progress before the job finishes", %{organization_id: organization_id} do
      user_job =
        UserJob.create_user_job(%{
          status: "pending",
          type: CollectionPrimaryPhone.job_type(),
          total_tasks: 1,
          tasks_done: 0,
          all_tasks_created: true,
          organization_id: organization_id,
          errors: %{}
        })

      assert {:ok, %{error: error}} =
               CollectionPrimaryPhone.get_report(organization_id, %{user_job_id: user_job.id})

      assert error =~ "in progress"
    end
  end
end
