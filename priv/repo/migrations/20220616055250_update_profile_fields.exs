defmodule Glific.Repo.Migrations.UpdateProfileFields do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      remove(:profile_type, :string)
      add(:type, :string)
    end

    create unique_index(:profiles, [:name, :type, :contact_id, :organization_id])
  end
end
