defmodule Glific.Repo.Migrations.AddHourlyTriggers do
  use Ecto.Migration

  def change do
    add_hour_column()
  end

  defp add_hour_column do
    alter table(:triggers) do
      # if frequency is hourly, the hours that it repeats
      # 1 - 12:00AM, 23 - 11:00PM
      add :hours, {:array, :integer}, default: []

    end
  end
end
