defmodule Glific.Repo.Migrations.AddDescColumnInFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :description, :string
    end
  end
end
