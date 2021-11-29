defmodule Glific.Repo.Migrations.DropObanBeats do
  use Ecto.Migration
  @global_schema Application.fetch_env!(:glific, :global_schema)

  def up do
    drop_if_exists table("oban_beats")
    drop_if_exists table("oban_beats", prefix: @global_schema)
  end

  def down do
    # No going back!
  end
end
