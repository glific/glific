defmodule Glific.Repo.Migrations.InOfficeFlow do
  use Ecto.Migration

  def change do
    organization
  end

  defp organization do
    alter table(:organizations) do
      add :in_office, :jsonb, comment: "JSON object of the in office information"
    end
  end
end
