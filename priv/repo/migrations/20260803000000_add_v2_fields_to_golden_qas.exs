defmodule Glific.Repo.Migrations.AddV2FieldsToGoldenQas do
  use Ecto.Migration

  def change do
    alter table(:golden_qas) do
      add :total_items, :integer, comment: "total items in the dataset"
    end
  end
end
