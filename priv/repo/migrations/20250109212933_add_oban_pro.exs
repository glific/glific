defmodule Glific.Repo.Migrations.AddObanPro do
  use Ecto.Migration

  # Oban Pro is no longer used; keep this migration as a no-op to preserve
  # numbering for existing deployments.
  def up, do: :ok

  def down, do: :ok
end
