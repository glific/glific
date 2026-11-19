defmodule Glific.Repo.Migrations.ChangeVersionsOrganizationFkToDeleteAll do
  use Ecto.Migration

  # validate: false (NOT VALID) skips the scan of existing rows, so the swap doesn't block
  # writes to versions; the follow-up migration validates them under a lighter lock.
  def change do
    alter table(:versions) do
      modify :organization_id,
             references(:organizations, on_delete: :delete_all, validate: false),
             null: true,
             comment: "Unique organization ID.",
             from: references(:organizations, on_delete: :nilify_all)
    end
  end
end
