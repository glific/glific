defmodule Glific.Repo.Migrations.AddGlobalFields do
  use Ecto.Migration

  def change do
    organizations()
  end

  defp organizations do
    alter table(:organizations) do
      add :fields, :map,
      default: %{},
      comment: "Labels and values of the NGO generated global fields"
    end
  end
end
