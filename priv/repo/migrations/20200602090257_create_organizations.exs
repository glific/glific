defmodule Glific.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :string, null: false
      add :contact_name, :string, null: false
      add :email, :string, null: false
      add :bsp, :string
      add :bsp_id, references(:bsps, on_delete: :nothing), null: false
      add :bsp_key, :string, null: false
      add :wa_number, :string, null: false

      timestamps()
    end
  end
end
