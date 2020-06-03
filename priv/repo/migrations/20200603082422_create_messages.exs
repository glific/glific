defmodule Glific.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do

      timestamps()
    end

  end
end
