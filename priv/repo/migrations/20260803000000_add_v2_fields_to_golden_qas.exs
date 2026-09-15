defmodule Glific.Repo.Migrations.AddV2FieldsToGoldenQas do
  use Ecto.Migration

  def change do
    alter table(:golden_qas) do
      add :total_items, :integer, default: 0, null: false, comment: "total items in the dataset"
    end
  end
end
