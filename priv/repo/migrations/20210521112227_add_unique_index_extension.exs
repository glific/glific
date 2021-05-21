defmodule Glific.Repo.Migrations.AddUniqueIndexExtension do
  use Ecto.Migration

  def change do
    extensions_index()
  end

  defp extensions_index do
    create unique_index(:extensions, [:module, :name, :organization_id])
    create index(:extensions, :organization_id)
  end
end
