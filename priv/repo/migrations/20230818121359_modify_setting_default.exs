defmodule Glific.Repo.Migrations.ModifySettingDefault do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      modify :setting, :jsonb, default: "{}"
    end
  end
end
