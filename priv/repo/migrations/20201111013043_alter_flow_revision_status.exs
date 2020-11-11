defmodule Glific.Repo.Migrations.AlterFlowRevisionStatus do
  use Ecto.Migration

  import Ecto.Query, warn: false

  alias Glific.{
    Flows.FlowContext,
    Flows.FlowRevision,
    Repo
  }

  def up do
    # update status of flow revision
    from([fr] in FlowRevision,
      where: fr.status == "done",
      update: [set: [status: "published"]]
    )
    |> Repo.update_all([])

    # update status of flow context
    from([fc] in FlowContext,
      where: fc.status == "done",
      update: [set: [status: "published"]]
    )
    |> Repo.update_all([])
  end

  def down do
    # update status of flow revision
    from([fr] in FlowRevision,
      where: fr.status == "published",
      update: [set: [status: "done"]]
    )
    |> Repo.update_all([])

    # update status of flow context
    from([fc] in FlowContext,
      where: fc.status == "published",
      update: [set: [status: "done"]]
    )
    |> Repo.update_all([])
  end
end
