defmodule Glific.Repo.Migrations.AddCustomUiToInteractiveMessageTypeEnum do
  use Ecto.Migration

  # ALTER TYPE ... ADD VALUE cannot run inside the migration's default transaction,
  # so we disable it for this migration.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("ALTER TYPE interactive_message_type_enum ADD VALUE IF NOT EXISTS 'custom_ui'")
  end

  # Postgres cannot drop a value from an enum type, so there is nothing to
  # reverse here. Rolling back this migration is a no-op by design.
  def down, do: :ok
end
