defmodule Glific.Groups.WAGroupMemberImportTest do
  use Glific.DataCase, async: false

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Groups.WAGroupMemberImport,
    Jobs.UserJob,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  import Ecto.Query

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

    # the acting phone's contact must be a group admin for Maytapi add to be allowed
    {:ok, _} =
      ContactWAGroups.create_contact_wa_group(%{
        contact_id: wa_managed_phone.contact_id,
        wa_group_id: wa_group.id,
        organization_id: organization.id,
        is_admin: true
      })

    %{organization_id: organization.id, wa_group: wa_group}
  end

  defp member_ids(wa_group_id) do
    ContactWAGroup
    |> where([c], c.wa_group_id == ^wa_group_id)
    |> select([c], c.contact_id)
    |> Repo.all()
  end

  test "imports members (phone + name) — creates contacts and links them", %{
    organization_id: org_id,
    wa_group: wa_group
  } do
    Tesla.Mock.mock(fn %{method: :post} ->
      {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}
    end)

    csv = "phone,name\n919900112233,Alice\n919900112244,Bob\n"

    assert {:ok, %{status: _}} =
             WAGroupMemberImport.import_members(org_id, wa_group.id, data: csv)

    # one chunk job is enqueued; run it
    assert %{success: 1} = Oban.drain_queue(queue: :wa_group, with_scheduled: true)

    for {phone, name} <- [{"919900112233", "Alice"}, {"919900112244", "Bob"}] do
      assert {:ok, contact} = Repo.fetch_by(Contact, %{phone: phone, organization_id: org_id})
      # name from the CSV is applied
      assert contact.name == name
      assert contact.id in member_ids(wa_group.id)
    end

    assert %UserJob{type: "wa_group_member_import", total_tasks: 1, tasks_done: 1, errors: errors} =
             Repo.get_by(UserJob, type: "wa_group_member_import")

    assert errors["errors"] == %{}
  end

  test "records phones in the UserJob errors when the Maytapi add fails", %{
    organization_id: org_id,
    wa_group: wa_group
  } do
    Tesla.Mock.mock(fn %{method: :post} ->
      {:ok,
       %Tesla.Env{
         status: 200,
         body: Jason.encode!(%{"success" => false, "message" => "ADD_FAILED"})
       }}
    end)

    csv = "phone\n919900112233\n"

    assert {:ok, _} = WAGroupMemberImport.import_members(org_id, wa_group.id, data: csv)
    assert %{success: 1} = Oban.drain_queue(queue: :wa_group, with_scheduled: true)

    # the contact is created (row processing runs first), but the WA add failed
    # so it isn't linked, and the phone is recorded against the job.
    assert {:ok, contact} =
             Repo.fetch_by(Contact, %{phone: "919900112233", organization_id: org_id})

    refute contact.id in member_ids(wa_group.id)

    # a batch add failure is recorded with a clear, member-scoped status (the
    # raw Maytapi reason is logged, not stamped into each member row)
    user_job = Repo.get_by(UserJob, type: "wa_group_member_import")
    assert user_job.errors["errors"]["919900112233"] == "Could not be added to the WhatsApp group"
  end
end
