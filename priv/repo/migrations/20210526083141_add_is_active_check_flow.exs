defmodule Glific.Repo.Migrations.AddIsActiveCheckFlow do
  use Ecto.Migration

  def change do
    flows()
  end

  defp flows do
    alter table(:flows) do
      add :is_active, :boolean,
        default: true,
        comment: "Whether flows are currently in use or not"
    end
  end
end
