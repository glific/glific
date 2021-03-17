defmodule Glific.Repo.Migrations.V0_11_6_AlterGlificTables do
  use Ecto.Migration

  def change do
    alter_user_contact_id_contraints()
  end

  defp alter_user_contact_id_contraints do
    drop constraint(:users, "users_contact_id_fkey")
    drop_if_exists index(:users, [:contact_id])

    alter table(:users) do
      modify :contact_id, references(:contacts, on_delete: :delete_all)
    end
  end
end
