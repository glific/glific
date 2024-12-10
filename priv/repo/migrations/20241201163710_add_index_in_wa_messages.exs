defmodule Glific.Repo.Migrations.AddIndexInWaMessages do
  use Ecto.Migration

  def change do
    create index(:wa_messages, [:bsp_id, :organization_id])
  end
end
