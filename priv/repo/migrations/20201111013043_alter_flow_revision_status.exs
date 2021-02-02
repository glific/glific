defmodule Glific.Repo.Migrations.AlterFlowRevisionStatus do
  use Ecto.Migration

  import Ecto.Query, warn: false

  alias Glific.{
    Flows.FlowContext,
    Flows.FlowRevision,
    Repo
  }

  defp run_query(query),
    do: Repo.update_all(query, [], skip_organization_id: true)

  def up do
    # update status of flow revision
    from([fr] in FlowRevision,
      where: fr.status == "done",
      update: [set: [status: "published"]]
    )
    |> run_query()

    # update status of flow context
    from([fc] in FlowContext,
      where: fc.status == "done",
      update: [set: [status: "published"]]
    )
    |> run_query()
  end

  def down do
    # update status of flow revision
    from([fr] in FlowRevision,
      where: fr.status == "published",
      update: [set: [status: "done"]]
    )
    |> run_query()

    # update status of flow context
    from([fc] in FlowContext,
      where: fc.status == "published",
      update: [set: [status: "done"]]
    )
    |> run_query()
  end
end
