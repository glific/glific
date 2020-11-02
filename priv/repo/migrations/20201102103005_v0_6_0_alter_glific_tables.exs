defmodule Glific.Repo.Migrations.V0_6_0_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.6.0 Alter Glific tables
  """

  def change do
    messages()
  end

  defp messages do
    alter table(:messages) do
      # it will be null for regular messages
      add :flow_id, references(:flows, on_delete: :nilify_all), null: true
    end
  end
end
