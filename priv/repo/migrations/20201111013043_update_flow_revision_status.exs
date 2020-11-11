defmodule Glific.Repo.Migrations.UpdateFlowRevisionStatus do
  use Ecto.Migration

  import Ecto.Query, warn: false

  alias Glific.{
    Flows.FlowRevision,
    Repo
  }

  def up do
    from([fr] in FlowRevision,
      where: fr.status == "done",
      update: [set: [status: "published"]]
    )
    |> Repo.update_all([])
  end

  def down do
    from([fr] in FlowRevision,
      where: fr.status == "published",
      update: [set: [status: "done"]]
    )
    |> Repo.update_all([])
  end
end
