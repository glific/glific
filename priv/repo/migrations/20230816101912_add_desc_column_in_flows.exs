defmodule Glific.Repo.Migrations.AddDescColumnInFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :description, :text
    end
  end
end
