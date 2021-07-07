defmodule Glific.Repo.Migrations.AddInteractiveMessage do
  use Ecto.Migration

  def change do
    interactive()
  end

  defp interactive do
    create table(:interactives, comment: "Lets add interactive messages here") do
      add :title, :string, comment: "The title of the interactive message"

      add :type, :string, comment: "The type of interactive message- quick_reply or list"

      add :interactive_content, :jsonb,
        default: "[]",
        comment: "Interactive content of the message stored in form of json"

      add :organization_id, references(:organizations, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:interactives, [:title, :type, :organization_id])
    create index(:interactives, :organization_id)
  end
end
