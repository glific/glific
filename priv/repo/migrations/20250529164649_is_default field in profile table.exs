defmodule Glific.Repo.Migrations.IsDefaultFieldInProfileTable do
  use Ecto.Migration

  def change do
alter table(:profiles) do
      add :is_default, :boolean, default: false
    end
  end
end
