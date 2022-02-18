defmodule Glific.Repo.Migrations.OrgSuspend do
  use Ecto.Migration

  def change do
    organizations()
  end

  defp organizations do
    alter table(:organizations) do
      add :is_suspended, :boolean,
        default: false,
        comment: "Organizations that have been temporarily suspended from sending messages"

      add :suspended_until, :utc_datetime,
        null: true,
        comment:
          "Till when does the suspension last, this is typically the start of the next day in the org's timezone"
    end
  end
end
