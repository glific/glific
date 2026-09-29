defmodule Glific.Repo.Migrations.DropOpenaiAssistantTables do
  @moduledoc """
  Drops the legacy OpenAI assistant tables, superseded by the unified API tables
  (assistants, assistant_config_versions, knowledge_bases, knowledge_base_versions).

  Rows were backfilled into the new tables before this ran. The data is gone, so
  down/0 is a no-op — it doesn't recreate the (now empty) tables, and stays
  reversible so a rollback to an earlier state isn't blocked. up/0 uses
  drop_if_exists so re-migrating after such a rollback stays safe.
  """

  use Ecto.Migration

  def up do
    # openai_assistants holds the FK to openai_vector_stores, so it drops first.
    drop_if_exists table(:openai_assistants)
    drop_if_exists table(:openai_vector_stores)
  end

  def down, do: :ok
end
