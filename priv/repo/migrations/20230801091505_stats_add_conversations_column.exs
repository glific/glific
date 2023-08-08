defmodule Glific.Repo.Migrations.StatsAddConversationsColumn do
  use Ecto.Migration

  def change do
    alter table(:stats) do
      add :conversations, :integer, default: 0
    end
  end
end
