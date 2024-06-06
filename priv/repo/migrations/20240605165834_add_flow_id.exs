defmodule Glific.Repo.Migrations.AddFlowId do
  use Ecto.Migration

  def change do
    alter table(:tickets) do
      add :flow_id, references(:flows, on_delete: :delete_all),
        null: true,
        comment: "Flow ID"
    end
  end
end
