defmodule Glific.Repo.Migrations.UpgradeObanProToV1_6 do
  use Ecto.Migration

  def up, do: Oban.Pro.Migration.up(version: "1.6.0", prefix: "global")

  def down, do: Oban.Pro.Migration.down(version: "1.5.0", prefix: "global")
end
