defmodule Glific.Groups.WAGroupPhoneTest do
  use Glific.DataCase, async: false

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Fixtures,
    Groups.WAGroupPhone,
    Repo,
    Seeds.SeedsDev,
    WAManagedPhones,
    WAMessages
  }

  setup do
    organization = SeedsDev.seed_organizations()
    %{organization_id: organization.id}
  end

  # The shared wa_managed_phone_fixture hardcodes the underlying contact's
  # phone, so only one managed phone per org can be inserted through it.
  # Tests that need a second one (e.g. partial-primary index, duplicate-group
  # backfill) build the WAManagedPhone directly.
  defp insert_wa_managed_phone(org_id, phone) do
    {:ok, contact} =
      Contacts.maybe_create_contact(%{
        phone: phone,
        organization_id: org_id,
        contact_type: "WA"
      })

    {:ok, wa_managed_phone} =
      WAManagedPhones.create_wa_managed_phone(%{
        phone: phone,
        phone_id: System.unique_integer([:positive]),
        status: "active",
        organization_id: org_id,
        contact_id: contact.id
      })

    wa_managed_phone
  end

  describe "changeset/2" do
    test "valid attrs produce a valid changeset", %{organization_id: org_id} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      changeset =
        WAGroupPhone.changeset(%WAGroupPhone{}, %{
          wa_group_id: group.id,
          wa_managed_phone_id: phone.id,
          organization_id: org_id,
          is_primary: true,
          is_active: true
        })

      assert changeset.valid?
    end

    test "requires wa_group_id, wa_managed_phone_id, organization_id" do
      changeset = WAGroupPhone.changeset(%WAGroupPhone{}, %{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.wa_group_id
      assert "can't be blank" in errors.wa_managed_phone_id
      assert "can't be blank" in errors.organization_id
    end

    test "is_primary defaults to false and is_active defaults to true", %{
      organization_id: org_id
    } do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      {:ok, row} =
        %WAGroupPhone{}
        |> WAGroupPhone.changeset(%{
          wa_group_id: group.id,
          wa_managed_phone_id: phone.id,
          organization_id: org_id
        })
        |> Repo.insert()

      assert row.is_primary == false
      assert row.is_active == true
    end
  end

  describe "unique constraints" do
    test "duplicate (wa_group_id, wa_managed_phone_id) is rejected", %{organization_id: org_id} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      attrs = %{
        wa_group_id: group.id,
        wa_managed_phone_id: phone.id,
        organization_id: org_id
      }

      {:ok, _} =
        %WAGroupPhone{}
        |> WAGroupPhone.changeset(attrs)
        |> Repo.insert()

      assert {:error, changeset} =
               %WAGroupPhone{}
               |> WAGroupPhone.changeset(attrs)
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).wa_group_id
    end

    test "partial unique index rejects a second primary for the same group", %{
      organization_id: org_id
    } do
      phone1 = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})
      phone2 = insert_wa_managed_phone(org_id, "919999990002")

      group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone1.id
        })

      {:ok, _} =
        %WAGroupPhone{}
        |> WAGroupPhone.changeset(%{
          wa_group_id: group.id,
          wa_managed_phone_id: phone1.id,
          organization_id: org_id,
          is_primary: true
        })
        |> Repo.insert()

      assert {:error, changeset} =
               %WAGroupPhone{}
               |> WAGroupPhone.changeset(%{
                 wa_group_id: group.id,
                 wa_managed_phone_id: phone2.id,
                 organization_id: org_id,
                 is_primary: true
               })
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).is_primary
    end

    test "partial unique index permits multiple non-primary memberships per group", %{
      organization_id: org_id
    } do
      phone1 = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})
      phone2 = insert_wa_managed_phone(org_id, "919999990002")

      group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone1.id
        })

      {:ok, _} =
        %WAGroupPhone{}
        |> WAGroupPhone.changeset(%{
          wa_group_id: group.id,
          wa_managed_phone_id: phone1.id,
          organization_id: org_id,
          is_primary: false
        })
        |> Repo.insert()

      assert {:ok, _} =
               %WAGroupPhone{}
               |> WAGroupPhone.changeset(%{
                 wa_group_id: group.id,
                 wa_managed_phone_id: phone2.id,
                 organization_id: org_id,
                 is_primary: false
               })
               |> Repo.insert()
    end
  end

  describe "Phase 1 backfill" do
    test "creates one primary membership per existing wa_group (including duplicate-group rows) and stamps wa_messages.wa_managed_phone_id",
         %{organization_id: org_id} do
      phone1 = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})
      phone2 = insert_wa_managed_phone(org_id, "919999990002")

      # Two wa_groups with the same bsp_id but different phones — the
      # duplicate-group case Phase 5 will eventually merge.
      group1 =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone1.id,
          bsp_id: "duplicate@g.us",
          label: "dup-1"
        })

      group2 =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone2.id,
          bsp_id: "duplicate@g.us",
          label: "dup-2"
        })

      # A wa_message that hasn't been stamped with wa_managed_phone_id yet.
      {:ok, message} =
        WAMessages.create_message(%{
          body: "hello",
          flow: :inbound,
          type: :text,
          bsp_id: "msg-#{System.unique_integer([:positive])}",
          bsp_status: :enqueued,
          contact_id: phone1.contact_id,
          organization_id: org_id,
          wa_group_id: group1.id
        })

      # Start with a clean wa_groups_phones table for this org so the assertions
      # don't depend on anything earlier in the test setup.
      Repo.delete_all(from(p in WAGroupPhone, where: p.organization_id == ^org_id))

      Repo.query!(
        """
        INSERT INTO wa_groups_phones (
          wa_group_id, wa_managed_phone_id, organization_id,
          is_primary, is_active, inserted_at, updated_at
        )
        SELECT id, wa_managed_phone_id, organization_id, TRUE, TRUE, NOW(), NOW()
        FROM wa_groups
        WHERE organization_id = $1
        ON CONFLICT (wa_group_id, wa_managed_phone_id) DO NOTHING
        """,
        [org_id]
      )

      Repo.query!(
        """
        UPDATE wa_messages m
        SET wa_managed_phone_id = g.wa_managed_phone_id
        FROM wa_groups g
        WHERE m.wa_group_id = g.id
          AND m.wa_managed_phone_id IS NULL
          AND m.organization_id = $1
        """,
        [org_id]
      )

      memberships =
        Repo.all(
          from p in WAGroupPhone,
            where: p.organization_id == ^org_id and p.wa_group_id in [^group1.id, ^group2.id],
            order_by: p.wa_group_id
        )

      assert length(memberships) == 2

      for m <- memberships do
        assert m.is_primary == true
        assert m.is_active == true
      end

      [m1, m2] = memberships
      assert {m1.wa_group_id, m1.wa_managed_phone_id} == {group1.id, phone1.id}
      assert {m2.wa_group_id, m2.wa_managed_phone_id} == {group2.id, phone2.id}

      reloaded = Repo.get!(Glific.WAGroup.WAMessage, message.id)
      assert reloaded.wa_managed_phone_id == phone1.id
    end

    test "backfill is idempotent and does not duplicate rows", %{organization_id: org_id} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      _group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      Repo.delete_all(from(p in WAGroupPhone, where: p.organization_id == ^org_id))

      run_backfill = fn ->
        Repo.query!(
          """
          INSERT INTO wa_groups_phones (
            wa_group_id, wa_managed_phone_id, organization_id,
            is_primary, is_active, inserted_at, updated_at
          )
          SELECT id, wa_managed_phone_id, organization_id, TRUE, TRUE, NOW(), NOW()
          FROM wa_groups
          WHERE organization_id = $1
          ON CONFLICT (wa_group_id, wa_managed_phone_id) DO NOTHING
          """,
          [org_id]
        )
      end

      run_backfill.()
      first_count = Repo.aggregate(WAGroupPhone, :count, :id)
      run_backfill.()
      assert Repo.aggregate(WAGroupPhone, :count, :id) == first_count
    end
  end

  # Sanity check that the new association is reachable from WAGroup,
  # covering the schema change in lib/glific/groups/wa_group.ex.
  describe "WAGroup association" do
    test "has_many :wa_groups_phones loads membership rows", %{organization_id: org_id} do
      phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: phone.id
        })

      _ =
        Fixtures.wa_group_phone_fixture(%{
          wa_group_id: group.id,
          wa_managed_phone_id: phone.id,
          organization_id: org_id,
          is_primary: true
        })

      reloaded = Repo.preload(group, :wa_groups_phones)
      assert [%WAGroupPhone{is_primary: true}] = reloaded.wa_groups_phones
    end
  end
end
