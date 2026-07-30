defmodule Glific.Scripts.NormalizeContactPhonesTest do
  use Glific.DataCase, async: true

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Groups,
    Messages.Message,
    Repo,
    Scripts.NormalizeContactPhones
  }

  @canonical "919917443992"

  setup %{organization_id: organization_id} do
    %{organization_id: organization_id}
  end

  describe "audit/1" do
    test "classifies a raw variant as a rename without writing", %{
      organization_id: organization_id
    } do
      contact = raw_contact(organization_id, "+91 99174-43992")

      report = report_for(NormalizeContactPhones.audit(organization_id: organization_id))

      assert report.rename >= 1
      assert sample_ids(report, :rename) |> Enum.member?(contact.id)
      assert Repo.get!(Contact, contact.id).phone == "+91 99174-43992"
    end

    test "classifies a raw variant colliding with a canonical row as a duplicate", %{
      organization_id: organization_id
    } do
      canonical = Fixtures.contact_fixture(%{organization_id: organization_id, phone: @canonical})
      loser = raw_contact(organization_id, "+#{@canonical}")

      report = report_for(NormalizeContactPhones.audit(organization_id: organization_id))

      assert sample_ids(report, :duplicate) |> Enum.member?(loser.id)
      assert report.merged == 0
      assert Repo.get!(Contact, canonical.id)
      assert Repo.get!(Contact, loser.id)
    end

    test "reports two raw variants of one number as a rename plus a duplicate", %{
      organization_id: organization_id
    } do
      first = raw_contact(organization_id, "+#{@canonical}")
      second = raw_contact(organization_id, "91 99174 43992")

      report = report_for(NormalizeContactPhones.audit(organization_id: organization_id))

      assert sample_ids(report, :rename) |> Enum.member?(first.id)
      assert sample_ids(report, :duplicate) |> Enum.member?(second.id)
    end

    test "leaves simulator and unparseable numbers out of the rewrite buckets", %{
      organization_id: organization_id
    } do
      simulator = raw_contact(organization_id, "9876543210_7")
      unparseable = raw_contact(organization_id, "9917443992")

      report = report_for(NormalizeContactPhones.audit(organization_id: organization_id))

      refute sample_ids(report, :rename) |> Enum.member?(simulator.id)
      refute sample_ids(report, :duplicate) |> Enum.member?(simulator.id)
      assert sample_ids(report, :unparseable) |> Enum.member?(unparseable.id)
      assert report.simulator >= 1
    end
  end

  describe "run/1" do
    test "rewrites a raw variant to its canonical form", %{organization_id: organization_id} do
      contact = raw_contact(organization_id, "+91 99174-43992")

      NormalizeContactPhones.run(organization_id: organization_id, dry_run: false)

      assert Repo.get!(Contact, contact.id).phone == @canonical
    end

    test "is idempotent", %{organization_id: organization_id} do
      contact = raw_contact(organization_id, "+#{@canonical}")

      NormalizeContactPhones.run(organization_id: organization_id, dry_run: false)
      second = report_for(NormalizeContactPhones.run(organization_id: organization_id))

      assert Repo.get!(Contact, contact.id).phone == @canonical
      refute sample_ids(second, :rename) |> Enum.member?(contact.id)
      refute sample_ids(second, :duplicate) |> Enum.member?(contact.id)
    end

    test "collapses two raw variants of the same number", %{organization_id: organization_id} do
      first = raw_contact(organization_id, "+#{@canonical}")
      second = raw_contact(organization_id, "91 99174 43992")

      NormalizeContactPhones.run(
        organization_id: organization_id,
        dry_run: false,
        merge: true
      )

      assert Repo.get!(Contact, first.id).phone == @canonical
      refute Repo.get(Contact, second.id)
    end

    test "leaves duplicates untouched unless merge is requested", %{
      organization_id: organization_id
    } do
      Fixtures.contact_fixture(%{organization_id: organization_id, phone: @canonical})
      loser = raw_contact(organization_id, "+#{@canonical}")

      NormalizeContactPhones.run(organization_id: organization_id, dry_run: false)

      assert Repo.get!(Contact, loser.id).phone == "+#{@canonical}"
    end
  end

  describe "run/1 with merge" do
    test "re-points messages onto the surviving contact and deletes the loser", %{
      organization_id: organization_id
    } do
      survivor =
        Fixtures.contact_fixture(%{organization_id: organization_id, phone: @canonical})

      loser = raw_contact(organization_id, "+#{@canonical}")

      message =
        Fixtures.message_fixture(%{
          organization_id: organization_id,
          sender_id: loser.id,
          receiver_id: loser.id,
          contact_id: loser.id
        })

      NormalizeContactPhones.run(
        organization_id: organization_id,
        dry_run: false,
        merge: true
      )

      refute Repo.get(Contact, loser.id)

      message = Repo.get!(Message, message.id)
      assert message.contact_id == survivor.id
      assert message.sender_id == survivor.id
      assert message.receiver_id == survivor.id
    end

    test "drops the losing group membership instead of violating its unique index", %{
      organization_id: organization_id
    } do
      survivor =
        Fixtures.contact_fixture(%{organization_id: organization_id, phone: @canonical})

      loser = raw_contact(organization_id, "+#{@canonical}")
      group = Fixtures.group_fixture(%{organization_id: organization_id})

      add_to_group(survivor, group, organization_id)
      add_to_group(loser, group, organization_id)

      NormalizeContactPhones.run(
        organization_id: organization_id,
        dry_run: false,
        merge: true
      )

      refute Repo.get(Contact, loser.id)
      assert group_contact_ids(group.id) == [survivor.id]
    end

    test "carries the later activity and the opt-in over to the survivor", %{
      organization_id: organization_id
    } do
      survivor =
        Fixtures.contact_fixture(%{
          organization_id: organization_id,
          phone: @canonical,
          optin_time: nil,
          optin_status: false,
          bsp_status: :hsm
        })

      recent = DateTime.utc_now() |> DateTime.truncate(:second)
      optin = DateTime.add(recent, -3600, :second)

      loser =
        raw_contact(organization_id, "+#{@canonical}", %{
          last_message_at: recent,
          bsp_status: :session_and_hsm,
          optin_time: optin,
          optin_status: true,
          optin_method: "BSP"
        })

      Repo.update_all(from(c in Contact, where: c.id == ^survivor.id),
        set: [last_message_at: DateTime.add(recent, -86_400, :second)]
      )

      NormalizeContactPhones.run(
        organization_id: organization_id,
        dry_run: false,
        merge: true
      )

      survivor = Repo.get!(Contact, survivor.id)

      refute Repo.get(Contact, loser.id)
      assert survivor.bsp_status == :session_and_hsm
      assert DateTime.compare(survivor.last_message_at, recent) == :eq
      assert survivor.optin_status
      assert survivor.optin_method == "BSP"
    end

    test "skips a duplicate whose losing row backs a user", %{organization_id: organization_id} do
      Fixtures.contact_fixture(%{organization_id: organization_id, phone: @canonical})

      user = Fixtures.user_fixture(%{organization_id: organization_id})
      loser = force_phone(user.contact_id, "+#{@canonical}")

      report =
        report_for(
          NormalizeContactPhones.run(
            organization_id: organization_id,
            dry_run: false,
            merge: true
          )
        )

      assert Repo.get!(Contact, loser.id).phone == "+#{@canonical}"
      assert sample_ids(report, :manual) |> Enum.member?(loser.id)
      assert report.merged == 0
    end
  end

  @spec raw_contact(non_neg_integer(), String.t(), map()) :: Contact.t()
  defp raw_contact(organization_id, phone, attrs \\ %{}) do
    contact =
      attrs
      |> Map.merge(%{organization_id: organization_id})
      |> Fixtures.contact_fixture()

    force_phone(contact.id, phone)
  end

  @spec force_phone(non_neg_integer(), String.t()) :: Contact.t()
  defp force_phone(contact_id, phone) do
    {1, _} =
      Repo.update_all(from(c in Contact, where: c.id == ^contact_id), set: [phone: phone])

    Repo.get!(Contact, contact_id)
  end

  @spec add_to_group(Contact.t(), Groups.Group.t(), non_neg_integer()) :: any()
  defp add_to_group(contact, group, organization_id) do
    {:ok, _} =
      Groups.create_contact_group(%{
        contact_id: contact.id,
        group_id: group.id,
        organization_id: organization_id
      })
  end

  @spec group_contact_ids(non_neg_integer()) :: [non_neg_integer()]
  defp group_contact_ids(group_id) do
    Groups.ContactGroup
    |> where([cg], cg.group_id == ^group_id)
    |> select([cg], cg.contact_id)
    |> Repo.all()
  end

  @spec report_for(map()) :: map()
  defp report_for(%{orgs: [report]}), do: report

  @spec sample_ids(map(), atom()) :: [non_neg_integer()]
  defp sample_ids(report, bucket) do
    report.samples
    |> Map.get(bucket, [])
    |> Enum.map(& &1.id)
  end
end
