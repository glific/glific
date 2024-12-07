defmodule Glific.Repo.Migrations.AddWaGroupFields do
  use Ecto.Migration

  def change do
    alter table(:wa_groups) do
      add :fields, :map, default: %{}, comment: "Labels and values of the NGO generated fields for the WA group"
    end

    alter table(:wa_messages) do
      add :flow_label, :string, comment: "Tagged flow label for WA messages"
    end

    # Adding group type to contact_field_scope enum
    execute("ALTER TYPE contact_field_scope_enum ADD VALUE IF NOT EXISTS 'wa_group'")

    # Modifying unique indexes to accomodate the scope
    execute("DROP INDEX IF EXISTS contacts_fields_shortcode_organization_id_index;")
    execute("CREATE UNIQUE INDEX contacts_fields_shortcode_organization_id_scope_index
    ON contacts_fields (shortcode, organization_id, scope);")

    execute("DROP INDEX IF EXISTS contacts_fields_name_organization_id_index;")
    execute("CREATE UNIQUE INDEX contacts_fields_name_organization_id_scope_index
    ON contacts_fields (name, organization_id, scope);")
  end
end
