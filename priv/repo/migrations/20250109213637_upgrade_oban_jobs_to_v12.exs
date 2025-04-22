defmodule Glific.Repo.Migrations.UpgradeObanJobsToV12 do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12, prefix: "global")
  end

  def down do
    Oban.Migration.down(version: 12, prefix: "global")
  end
end
