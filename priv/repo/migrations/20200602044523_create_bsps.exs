defmodule Glific.Repo.Migrations.CreateBsps do
  use Ecto.Migration

  def change do
    create table(:bsps) do
      add :name, :string
      add :url, :string
      add :api_end_point, :string

      timestamps()
    end
  end
end
