defmodule Glific.Repo.Migrations.AddGroupTypeInGroups do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      add :group_type, :string
    end
  end
end
