defmodule Glific.Repo.Migrations.AddRegxFlowToOrganization do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add(:regx_flow, :jsonb,
        after: :out_of_office,
        comment: "Regx flow config for the organization"
      )
    end
  end
end
