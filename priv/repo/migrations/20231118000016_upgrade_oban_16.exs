defmodule Glific.Repo.Migrations.AddObanProducers do
  use Ecto.Migration

  def up, do: Oban.Migrations.up(version: 11, prefix: "global")

  def down, do: Oban.Migrations.down(version: 11, prefix: "global")

end
