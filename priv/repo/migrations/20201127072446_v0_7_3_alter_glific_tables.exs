defmodule Glific.Repo.Migrations.V0_7_3_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.7.3 Alter Glific tables
  """

  def change do
    message_type_enum()
  end

  defp message_type_enum() do
    execute("ALTER TYPE message_type_enum ADD VALUE IF NOT EXISTS 'sticker';")
  end
end
