defmodule Glific.Repo.Migrations.AddForcedSuspensionEnum do
  use Ecto.Migration

  def change do
    execute("ALTER TYPE public.organization_status_enum ADD VALUE 'forced_suspension'")
  end
end
