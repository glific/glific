defmodule Glific.Repo.Migrations.AddCloneStatusToAssistants do
  use Ecto.Migration

  def change do
    alter table(:assistants) do
      add(:clone_status, :string, default: "none")
    end
  end
end
