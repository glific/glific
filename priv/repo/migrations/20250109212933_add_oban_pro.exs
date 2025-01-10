defmodule Glific.Repo.Migrations.AddObanPro do
  use Ecto.Migration

  def up, do: Oban.Pro.Migration.up()

  def down, do: Oban.Pro.Migration.down()
end
