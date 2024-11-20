defmodule Glific.Repo.Migrations.AddWaGroupFields do
  use Ecto.Migration
  # disabling transaction since enum modification doesn't work in transaction
  @disable_ddl_transaction true

  def change do
    alter table(:wa_groups) do
      add :fields, :map, default: %{}
    end

    # Adding group type to contact_field_scope enum
    execute("ALTER TYPE contact_field_scope_enum ADD VALUE IF NOT EXISTS 'group'")

    # Modifying unique indexes to accomodate the scope
    execute("DROP INDEX IF EXISTS contacts_fields_shortcode_organization_id_index;")
    execute("CREATE UNIQUE INDEX contacts_fields_shortcode_organization_id_scope_index
    ON contacts_fields (shortcode, organization_id, scope);")

    execute("DROP INDEX IF EXISTS contacts_fields_name_organization_id_index;")
    execute("CREATE UNIQUE INDEX contacts_fields_name_organization_id_scope_index
    ON contacts_fields (name, organization_id, scope);")
  end
end
