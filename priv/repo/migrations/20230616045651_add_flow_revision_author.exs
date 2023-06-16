defmodule Glific.Repo.Migrations.AddFlowRevisionAuthor do
  use Ecto.Migration

  def change do
    alter table(:flow_revisions) do
      # author of flow revision
      add(:user_id, references(:users, on_delete: :nilify_all), null: true)
  end
end
