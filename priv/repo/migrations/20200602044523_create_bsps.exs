defmodule Glific.Repo.Migrations.CreateBsps do
  use Ecto.Migration

  def change do
    create table(:bsps) do
      # The name of BSP
      add :name, :string
      # The name of url
      add :url, :string
      # The api end point for BSP
      add :api_end_point, :string

      timestamps()
    end
  end
end
