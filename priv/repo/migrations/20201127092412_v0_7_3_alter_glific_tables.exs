defmodule Glific.Repo.Migrations.V0_7_3_AlterGlificTables do
  @moduledoc """
  v0.7.3 Alter Glific tables
  """
  use Ecto.Migration
  @disable_ddl_transaction true

  def up do
    message_type_enum()
  end

  def down do
    # There is no easy way to drop an enum value. It is not supported.
  end

  defp message_type_enum() do
    execute "ALTER TYPE message_type_enum ADD VALUE IF NOT EXISTS 'sticker';"
  end
end
