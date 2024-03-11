defmodule Glific.Repo.Migrations.CreateAutoTranslationLogs do
  use Ecto.Migration

  def change do
    add_translate_logs()
  end

  defp add_translate_logs do
    create table(:translate_logs) do
      add :text, :text, comment: "Original text to be translated."

      add :translated_text, :text, comment: "Translated text."

      add :translation_engine, :string,
        comment: "Translation engine used: either Google Translate or Open AI."

      add :source_language, :string, comment: "Language of the original text to be translated."

      add :destination_language, :string, comment: "Language of the translated text."

      add :status, :boolean,
        comment: "Flag indicating whether the translation was successful or not."

      # Foreign key to organization, restricting the scope of this table to the specified organization.
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime_usec)
    end
  end
end
