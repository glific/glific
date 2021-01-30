defmodule Glific.Repo.Migrations.UpgradeObanJobsToV101 do
  use Ecto.Migration

  @global_schema Application.fetch_env!(:glific, :global_schema)

  def up do
    Oban.Migrations.up(version: 10, prefix: @global_schema)
  end

  def down do
    Oban.Migrations.down(version: 9, prefix: @global_schema)
  end

end
