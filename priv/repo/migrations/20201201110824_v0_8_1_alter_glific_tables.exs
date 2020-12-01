defmodule Glific.Repo.Migrations.V0_8_1_AlterGlificTables do
  @moduledoc """
  v0.7.3 Alter Glific tables
  """
  use Ecto.Migration
  @disable_ddl_transaction true

  def up do
    add_translations_to_session_templates()
  end

  def down do
    # There is no easy way to drop an enum value. It is not supported.
  end

  defp add_translations_to_session_templates() do
    alter table(:session_templates) do
      add :translations, :jsonb, default: "[]"
      remove :body
      remove :language_id
      remove :number_parameters
    end
  end
end
