defmodule Glific.Repo.Migrations.LanguageSupportInteractiveMessage do
  use Ecto.Migration

  @global_schema Application.fetch_env!(:glific, :global_schema)
  def change do
    interactive_templates()
  end

  defp interactive_templates() do
    alter table(:interactive_templates) do
      # Storing different translation of same interactive message
      add :translations, :map, default: %{},

      # Interactive messages are in a specific language
      add :language_id, references(:languages, on_delete: :restrict, prefix: @global_schema),
      null: false,
      comment: "Language of the interactive message"
    end
    create unique_index(:interactive_templates, [:label, :language_id, :organization_id])
  end
end
