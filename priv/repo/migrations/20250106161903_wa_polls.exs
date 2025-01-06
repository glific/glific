defmodule Glific.Repo.Migrations.WaPolls do
  use Ecto.Migration

  def change do
    create table(:wa_polls) do
      add :label, :string, null: false, comment: "Title of the whatsapp poll"

      add :poll_content, :map,
        default: %{},
        null: false,
        comment: "poll content"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    create unique_index(:wa_polls, [:label, :organization_id])
  end
end
