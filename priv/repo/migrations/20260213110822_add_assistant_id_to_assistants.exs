defmodule Glific.Repo.Migrations.AddAssistantIdToAssistants do
  use Ecto.Migration

  def up do
    alter table(:assistants) do
      add :assistant_display_id, :string,
        comment: "OpenAI-style assistant ID to display in the UI"
    end

    create unique_index(:assistants, [:assistant_display_id])
  end

  def down do
    drop_if_exists unique_index(:assistants, [:assistant_display_id])

    alter table(:assistants) do
      remove :assistant_display_id
    end
  end
end
