defmodule Glific.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    Oban.Migrations.up(prefix: @global_schema)
  end

  # We specify `version: 1` in `down`, ensuring that we'll roll all the way back down if
  # necessary, regardless of which version we've migrated `up` to.
  def down do
    Oban.Migrations.down(version: 1)
  end
end
