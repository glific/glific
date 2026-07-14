defmodule Glific.Repo.Migrations.CreateOrganizationStatusHistories do
  use Ecto.Migration

  def change do
    create table(:organization_status_histories) do
      add :previous_status, :organization_status_enum,
        comment: "Organization status before this transition; null for the first recorded change"

      add :new_status, :organization_status_enum,
        null: false,
        comment: "Organization status after this transition"

      add :reason, :string,
        comment: "Why the status changed, e.g. payment_default; null for manual changes"

      add :metadata, :map,
        default: %{},
        comment: "Optional structured context for the transition (e.g. billing details)"

      add :changed_at, :utc_datetime,
        null: false,
        comment: "Timestamp when the status transition was applied"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization whose status changed"

      timestamps(type: :utc_datetime)
    end

    create index(:organization_status_histories, [:organization_id, :changed_at])
    create index(:organization_status_histories, [:organization_id])
  end
end
