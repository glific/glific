defmodule Glific.Seeds.SeedsMigrationTest do
  use Glific.DataCase

  alias Glific.{Contacts.Contact, Fixtures, Repo, Seeds.SeedsMigration}

  test "migrate_data(:simulator) gives the seeded contacts a WhatsApp identity with their fields" do
    organization = Fixtures.organization_fixture(%{name: "Seeded org", shortcode: "seeded"})

    assert :ok = SeedsMigration.migrate_data(:simulator, organization)

    seeded =
      Repo.all(
        from(c in Contact,
          where:
            c.organization_id == ^organization.id and
              (like(c.name, "Glific Simulator %") or c.name == "SaaS Admin")
        ),
        skip_organization_id: true
      )

    assert length(seeded) == 6

    for contact <- seeded do
      assert %{contact: fields, identity: fields} = Fixtures.whatsapp_optin_fields(contact)
      assert fields.bsp_status == :session_and_hsm
    end
  end
end
