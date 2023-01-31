defmodule Glific.Repo.Migrations.AddSheetDataCount do
  use Ecto.Migration

  def change do
    alter table("sheets") do
      add :sheet_data_count, :integer
    end
  end
end
