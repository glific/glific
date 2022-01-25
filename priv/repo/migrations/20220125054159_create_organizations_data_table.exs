defmodule Glific.Repo.Migrations.CreateOrganizationsDataTable do
  use Ecto.Migration

  def change do
    organizations_data()
  end

  @doc """
  Create flow label to associate flow messages with label
  """
  def organizations_data do
    create table(:organizations_data) do
      add :key, :string, null: false, comment: "key of the data"

      add :value, :map,
        default: %{},
        comment: "Value it contains in the field"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"

      timestamps(type: :utc_datetime)
    end
  end
end
