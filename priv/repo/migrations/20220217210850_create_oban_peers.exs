defmodule Glific.Repo.Migrations.CreateObanPeers do
  use Ecto.Migration

  @global_schema Application.fetch_env!(:glific, :global_schema)

  def up, do: Oban.Migrations.up(version: 11, prefix: @global_schema)

  def down, do: Oban.Migrations.down(version: 1, prefix: @global_schema)
end
