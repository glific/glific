defmodule Glific.DigitalGreenTest do
  use Glific.DataCase

  alias Glific.{
    Clients.DigitalGreenDGSeed,
    Clients.DigitalGreen,
    Contacts,
    Flows.ContactField,
    Fixtures,
    Groups,
    Groups.Group,
    Seeds.SeedsDev
  }

  describe "digital green" do
    setup do
      organization = SeedsDev.seed_organizations()
      DigitalGreenDGSeed.seed_data([organization])
      :ok
    end

    test "testdaily/1 with valid data creates a group", attrs do
      enrolled_day = Timex.shift(Timex.now(), days: -10) |> Timex.to_date()
      next_flow_at = Timex.now()|> Timex.to_date()

      contact =
        Fixtures.contact_fixture(attrs)
        |> ContactField.do_add_contact_field("total_days", "total_days", "10", "string")
        |> ContactField.do_add_contact_field(
          "enrolled_day",
          "enrolled_day",
          enrolled_day,
          "string"
        )
        |> ContactField.do_add_contact_field(
          "initial_crop_day",
          "initial_crop_day",
          "10",
          "string"
        )
        |> ContactField.do_add_contact_field(
          "next_flow",
          "next_flow",
          "adoption",
          "string"
        )
        |> ContactField.do_add_contact_field(
          "next_flow_at",
          "next_flow_at",
          next_flow_at,
          "string"
        )

      updated_contact = Contacts.get_contact!(contact.id)

      webhook_fields = %{
        "contact" => %{"fields" => updated_contact.fields},
        "organization_id" => attrs.organization_id,
        "contact_id" => contact.id |> Integer.to_string()
      }

      DigitalGreen.webhook("daily", webhook_fields)
      updated_contact2 = Contacts.get_contact!(contact.id)

      {:ok, group} =
        Repo.fetch_by(Group, %{label: "adoption", organization_id: attrs.organization_id})

      info = Groups.info_group_contacts(group.id)|>IO.inspect
      assert updated_contact2.fields["total_days"]["value"] == 20
      assert info.total >= 0
    end
  end
end
