defmodule Glific.Repo.Migrations.DropUnscopedAssistantDisplayIdIndex do
  use Ecto.Migration

  def up do
    drop_if_exists index(:assistants, [:assistant_display_id],
                     name: :assistants_assistant_display_id_index
                   )
  end

  def down do
    :ok
  end
end
