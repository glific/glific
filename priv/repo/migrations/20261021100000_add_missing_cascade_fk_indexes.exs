defmodule Glific.Repo.Migrations.AddMissingCascadeFkIndexes do
  use Ecto.Migration

  # Without these, every ON DELETE CASCADE from contacts / wa_messages runs a sequential
  # scan of the child table, which makes org data erase time out on large tables.
  @disable_ddl_transaction true
  @disable_migration_lock true

  @indexes [
    {:tickets, :contact_id},
    {:contacts_wa_groups, :contact_id},
    {:wa_messages, :context_message_id}
  ]

  def up do
    Enum.each(@indexes, fn {table, column} ->
      name = "#{table}_#{column}_index"

      # A failed concurrent build leaves an INVALID index that create_if_not_exists would skip.
      if invalid_index?(name), do: execute("DROP INDEX CONCURRENTLY IF EXISTS #{name}")

      create_if_not_exists index(table, [column], concurrently: true)
    end)
  end

  def down do
    Enum.each(@indexes, fn {table, column} ->
      drop_if_exists index(table, [column], concurrently: true)
    end)
  end

  defp invalid_index?(name) do
    %{rows: rows} =
      repo().query!(
        "SELECT 1 FROM pg_index WHERE indexrelid = to_regclass($1) AND NOT indisvalid",
        [name]
      )

    rows != []
  end
end
