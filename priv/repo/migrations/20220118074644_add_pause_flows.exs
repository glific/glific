defmodule Glific.Repo.Migrations.AddPauseFlows do
  use Ecto.Migration

  def change do
    contacts()
  end

  defp contacts do
    alter table(:contacts) do
      add :flows_paused_at, :utc_datetime,
        default: nil,
        comment: "Is the flow paused for a particular contact"
    end
  end
end
