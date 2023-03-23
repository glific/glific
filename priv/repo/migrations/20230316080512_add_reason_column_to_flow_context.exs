defmodule Glific.Repo.Migrations.AddReasonColumnToFlowContext do
  use Ecto.Migration

  def change do
    alter table(:flow_contexts) do
      add :reason, :string
    end
  end
end
