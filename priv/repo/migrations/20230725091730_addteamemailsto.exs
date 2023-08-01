defmodule MyApp.Repo.Migrations.AddTeamEmailsToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :team_emails, :map
    end
  end
end
