defmodule Glific.Repo.Migrations.CreateBsps do
  use Ecto.Migration

  def change do
    create table(:bsps) do
      # The name of BSP
      add :name, :string, null: false
      # The url of BSP
      add :url, :string, null: false
      # The api end point for BSP
      add :api_end_point, :string, null: false

      timestamps()
    end

    create unique_index(:bsps, [:name, :url, :api_end_point])
  end
end
