defmodule Glific.Contacts.IdentityBackfillWorkerTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Contacts.IdentityBackfillWorker,
    Fixtures,
    Repo
  }

  defp whatsapp_identities do
    ContactIdentity
    |> where([i], i.channel == :whatsapp)
    |> Repo.all(skip_organization_id: true)
  end

  defp without_identities do
    Repo.delete_all(ContactIdentity, skip_organization_id: true)
  end

  defp backfill_jobs do
    Oban.Job
    |> where([j], j.worker == "Glific.Contacts.IdentityBackfillWorker")
    |> Repo.all(prefix: "global")
  end

  defp insert_contact(organization_id, phone) do
    Repo.insert_all(
      Contact,
      [
        %{
          phone: phone,
          name: "Backfill",
          language_id: 1,
          organization_id: organization_id,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ],
      returning: [:id]
    )
    |> elem(1)
    |> hd()
    |> Map.fetch!(:id)
  end

  test "start/0 gives every contact with a phone its identity", %{
    organization_id: organization_id
  } do
    contact = Fixtures.contact_fixture(%{organization_id: organization_id})
    without_identities()

    assert {:ok, _job} = IdentityBackfillWorker.start()
    Oban.drain_queue(queue: :purge, with_scheduled: true)

    assert %{contact_id: contact_id} =
             Enum.find(whatsapp_identities(), &(&1.identifier == contact.phone))

    assert contact_id == contact.id
  end

  test "is idempotent", %{organization_id: organization_id} do
    Fixtures.contact_fixture(%{organization_id: organization_id})
    without_identities()

    IdentityBackfillWorker.start()
    Oban.drain_queue(queue: :purge, with_scheduled: true)
    count = length(whatsapp_identities())

    IdentityBackfillWorker.start()
    Oban.drain_queue(queue: :purge, with_scheduled: true)

    assert count > 0
    assert count == length(whatsapp_identities())
  end

  test "covers contacts of every organization, with their own organization_id" do
    other_organization = Fixtures.organization_fixture()
    other = Fixtures.contact_fixture(%{organization_id: other_organization.id})
    without_identities()

    IdentityBackfillWorker.start()
    Oban.drain_queue(queue: :purge, with_scheduled: true)

    identity = Enum.find(whatsapp_identities(), &(&1.contact_id == other.id))
    assert identity.organization_id == other_organization.id
  end

  test "skips contacts without a phone", %{organization_id: organization_id} do
    contact_without_phone =
      Fixtures.contact_without_phone_fixture(%{organization_id: organization_id})

    without_identities()

    IdentityBackfillWorker.start()
    Oban.drain_queue(queue: :purge, with_scheduled: true)

    refute Enum.any?(whatsapp_identities(), &(&1.contact_id == contact_without_phone.id))
  end

  test "works through chunks, enqueuing the next from the last id", %{
    organization_id: organization_id
  } do
    ids = for index <- 1..3, do: insert_contact(organization_id, "9198765#{40_000 + index}")
    without_identities()

    assert :ok = perform_job(IdentityBackfillWorker, %{after_id: hd(ids) - 1})

    assert [%{args: %{"after_id" => next_id}}] = backfill_jobs()
    assert next_id == List.last(ids)
    assert Enum.all?(ids, fn id -> Enum.any?(whatsapp_identities(), &(&1.contact_id == id)) end)
  end

  test "stops when there are no contacts left" do
    assert :ok = perform_job(IdentityBackfillWorker, %{after_id: 2_000_000_000})
    assert [] == backfill_jobs()
  end
end
