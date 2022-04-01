defmodule Glific.Repo.Migrations.UpdateIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:messages, :context_message_id,
                           where: "context_message_id IS NOT NULL"
                         )

    create_if_not_exists index(:locations, :message_id)
    create_if_not_exists index(:locations, :organization_id)
    create_if_not_exists index(:locations, :contact_id)
  end
end
