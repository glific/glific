defmodule Glific.Repo.Migrations.FlowContextsIsTerminated do
  use Ecto.Migration

  def change do
    flow_contexts()
  end

  defp flow_contexts do
    alter table(:flow_contexts) do
      add :is_killed, :boolean,
        default: false,
        comment: "Did we kill this flow?"
    end
  end
end
