defmodule Glific.DigitalGreenTest do
  use Glific.DataCase

  alias Glific.{
    Clients.DigitalGreen,
    Clients.DigitalGreenDGSeed,
    Contacts,
    Fixtures,
    Groups,
    Groups.Group,
    Seeds.SeedsDev
  }

  describe "digital green webhook tests" do
    setup do
      organization = SeedsDev.seed_organizations()
      DigitalGreenDGSeed.seed_data([organization])
      :ok
    end

    test "webhook/2 with daily as first param should move contact to stage group based on total days, update number of days and add to next flow group",
         attrs do
      enrolled_day = Timex.shift(Timex.now(), days: -10) |> Timex.to_date()
      next_flow_at = Timex.now() |> Timex.to_date()

      dg_contact =
        attrs
        |> Map.merge(%{
          enrolled_day: enrolled_day,
          next_flow_at: next_flow_at,
          initial_crop_day: "16"
        })
        |> Fixtures.dg_contact_fixture()

      contact = Contacts.get_contact!(dg_contact.id)

      webhook_fields = %{
        "contact" => %{"fields" => contact.fields},
        "organization_id" => attrs.organization_id,
        "contact_id" => contact.id |> Integer.to_string()
      }

      {:ok, adoption_group} =
        Repo.fetch_by(Group, %{label: "adoption", organization_id: attrs.organization_id})

      adoption_group_info = Groups.info_group_contacts(adoption_group.id)

      {:ok, stage_2_group} =
        Repo.fetch_by(Group, %{label: "stage 2", organization_id: attrs.organization_id})

      stage_2_group_info = Groups.info_group_contacts(stage_2_group.id)

      DigitalGreen.webhook("daily", webhook_fields)

      updated_adoption_group_info = Groups.info_group_contacts(adoption_group.id)
      updated_stage_2_group_info = Groups.info_group_contacts(stage_2_group.id)

      assert updated_adoption_group_info.total >= adoption_group_info.total
      assert updated_stage_2_group_info.total >= stage_2_group_info.total
    end
  end
end
