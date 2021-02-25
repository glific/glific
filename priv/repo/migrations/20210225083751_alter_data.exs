defmodule Glific.Repo.Migrations.AlterData do
  use Ecto.Migration

  def change do
    users()
  end

  defp users do
    drop constraint(:users, "users_contact_id_fkey")
    drop_if_exists index(:users, [:contact_id])
    alter table(:users) do
      modify :contact_id, references(:contacts,  on_delete: :delete_all)
    end
  end
end
