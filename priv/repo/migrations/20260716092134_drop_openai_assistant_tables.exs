defmodule Glific.Repo.Migrations.DropOpenaiAssistantTables do
  @moduledoc """
  Drops the legacy OpenAI assistant tables, superseded by the unified API tables
  (assistants, assistant_config_versions, knowledge_bases, knowledge_base_versions).

  Rows were backfilled into the new tables before this ran. The drop is one-way —
  the data is gone — so down/0 refuses rather than recreate empty tables.
  """

  use Ecto.Migration

  def up do
    # openai_assistants holds the FK to openai_vector_stores, so it drops first.
    drop table(:openai_assistants)
    drop table(:openai_vector_stores)
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "irreversible: openai_assistants/openai_vector_stores were dropped and their data is gone"
  end
end
