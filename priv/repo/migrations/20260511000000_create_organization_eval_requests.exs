defmodule Glific.Repo.Migrations.CreateOrganizationEvalRequests do
  use Ecto.Migration

  def up do
    create table(:organization_eval_requests) do
      add(:status, :string, null: false, default: "requested")
      add(:organization_id, references(:organizations, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:organization_eval_requests, [:organization_id]))
  end

  def down do
    drop(table(:organization_eval_requests))
  end
end
