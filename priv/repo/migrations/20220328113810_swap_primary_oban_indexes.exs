defmodule Glific.Repo.Migrations.SwapPrimaryObanIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    create_if_not_exists index(
                           :oban_jobs,
                           [:state, :queue, :priority, :scheduled_at, :id],
                           concurrently: true,
                           prefix: @global_schema
                         )

    drop_if_exists index(
                     :oban_jobs,
                     [:queue, :state, :priority, :scheduled_at, :id],
                     prefix: @global_schema
                   )
  end
end
