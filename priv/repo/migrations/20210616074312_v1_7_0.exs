defmodule Glific.Repo.Migrations.V170 do
  use Ecto.Migration

  def change do
    alter_organization_with_status()
  end

  def abc do
    alter table(:organizations) do
      add :status, :boolean,
        default: false,
        comment: "Manual approval of an organization to trigger onboarding workflow"
    end
  end

end
