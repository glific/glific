defmodule Glific.Repo.Migrations.CreateProfiles do
  use Ecto.Migration

  @global_schema Application.compile_env!(:glific, :global_schema)

  def change do
    create table(:profiles) do
      add :name, :string, comment: "Name of the profile"
      add :profile_type, :string
      add :profile_registration_fields, :map
      add :contact_profile_fields, :map

      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "reference for the contact"

      add :language_id, references(:languages, on_delete: :delete_all, prefix: @global_schema),
        null: false,
        comment: "reference for the language"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "reference for the organization"

      timestamps(type: :utc_datetime)
    end

    create index(:profiles, :contact_id)
    create index(:profiles, :language_id)
    create index(:profiles, :organization_id)
  end
end
