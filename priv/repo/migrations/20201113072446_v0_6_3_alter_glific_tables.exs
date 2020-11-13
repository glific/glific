defmodule Glific.Repo.Migrations.V0_6_3_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.6.2 Alter Glific tables
  """

  import Ecto.Query, warn: false

  def change do
    users()

    contacts()
  end

  defp users() do
    alter table(:users) do
      add :is_restricted, :boolean, default: false
    end
  end

  def contacts() do
    alter table(:contacts) do
      add :last_communication_at, :utc_datetime
    end
  end
end
