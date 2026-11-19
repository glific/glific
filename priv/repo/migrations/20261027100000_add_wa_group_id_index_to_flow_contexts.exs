defmodule Glific.Repo.Migrations.AddWaGroupIdIndexToFlowContexts do
  use Ecto.Migration

  # Concurrent index builds cannot run inside a transaction or hold the Ecto
  # migration advisory lock — required on the large production flow_contexts table.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Backs FlowContext.mark_wa_flows_complete/3, which otherwise scans every flow context of
    # the org and can exceed the query timeout. Partial, since contact contexts leave it null.
    create_if_not_exists index(:flow_contexts, [:wa_group_id],
                           where: "wa_group_id IS NOT NULL",
                           concurrently: true,
                           comment: "Backs completing a WA group's open flow contexts"
                         )
  end
end
