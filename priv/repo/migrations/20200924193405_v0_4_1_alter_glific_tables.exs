defmodule Glific.Repo.Migrations.V041AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.4.1 Alter Glific tables
  """

  def change do
    organization_credentials()
  end

  defp organization_credentials do
    create table(:organization_credentials) do
      # shortcode for service name
      add :shortcode, :string

      # all the service keys which doesn't need ecryption
      add :keys, :jsonb, default: "{}"

      # we will keep these keys encrypted
      add :secrets, :jsonb, default: "{}"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organization_credentials, [:shortcode, :organization_id])
  end
end
