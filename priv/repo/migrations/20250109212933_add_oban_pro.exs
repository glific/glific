defmodule Glific.Repo.Migrations.AddObanPro do
  use Ecto.Migration

  def up, do: Oban.Pro.Migration.up(version: "1.5.0", prefix: "global")

  def down, do: Oban.Pro.Migration.down(prefix: "global")
end
