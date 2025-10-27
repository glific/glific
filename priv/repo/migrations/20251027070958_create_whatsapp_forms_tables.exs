defmodule Glific.Repo.Migrations.CreateWhatsappFormsTables do
  use Ecto.Migration

  def up do
    execute("""
      CREATE TYPE public.whatsapp_forms_status_enum AS ENUM (
        'draft',
        'published',
        'inactive'
      );
    """)

    create table(:whatsapp_forms) do
      add(:name, :string, null: false, comment: "Name of the form")
      add(:description, :text, comment: "Description of the form")
      add(:meta_flow_id, :text, null: false, comment: "ID of the form received from Meta")

      add(:status, :whatsapp_forms_status_enum,
        default: "draft",
        null: false,
        comment: "Current status of the form"
      )

      add(:definition, :jsonb, default: "{}", comment: "JSON of the form")
      add(:organization_id, references(:organizations, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:whatsapp_forms, [:name, :organization_id])
    create index(:whatsapp_forms, [:organization_id])
  end

  def down do
    drop_if_exists(table(:whatsapp_forms))

    execute("DROP TYPE IF EXISTS public.whatsapp_forms_status_enum;")
  end
end
