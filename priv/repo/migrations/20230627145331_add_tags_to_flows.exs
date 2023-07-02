defmodule Glific.Repo.Migrations.AddTagsToFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add(:tag_id, references(:tags, on_delete: :nothing))
    end

    alter table(:session_templates) do
      add(:tag_id, references(:tags, on_delete: :nothing))
    end
  end
end
