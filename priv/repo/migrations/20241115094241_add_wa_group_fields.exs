defmodule Glific.Repo.Migrations.AddWaGroupFields do
  use Ecto.Migration

  def change do
    alter table(:wa_groups) do
      add :fields, :map, default: %{}
    end
  end
end
