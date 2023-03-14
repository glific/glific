defmodule Glific.Repo.Migrations.AddUniqueIndexToNewContactIdForUsers do
  use Ecto.Migration

  def change do
    create unique_index(:users, [:contact_id], if_not_exists: true, name: "unique_contact_id_index")
  end
end
