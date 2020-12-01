defmodule Glific.Repo.Migrations.v0_8_1_AlterGlificTables do
  use Ecto.Migration

  def up do
    add_translations_to_session_templates()
  end

  def down do
    # There is no easy way to drop an enum value. It is not supported.
  end

  defp add_translations_to_session_templates() do
    alter table(:session_templates) do
      add :translations, :jsonb, default: "[]"
    end
  end
end
