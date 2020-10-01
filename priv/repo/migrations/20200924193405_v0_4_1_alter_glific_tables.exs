defmodule Glific.Repo.Migrations.V041AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.4.1 Alter Glific tables
  """

  def change do
    credentials()

    providers()

    chatbase_jobs()
  end

  defp providers do
    alter table("providers") do
      add :shortcode, :string, null: false
      add :group, :string

      add :is_required, :boolean, default: false

      # structure for keys
      add :keys, :jsonb, default: "{}"

      # structure for secrets
      add :secrets, :jsonb, default: "{}"

      remove :url
      remove :api_end_point
      remove :handler
      remove :worker
    end

    create unique_index(:providers, :shortcode)
  end

  defp credentials do
    create table(:credentials) do
      # all the service keys which doesn't need ecryption
      add :keys, :jsonb, default: "{}"

      # we will keep these keys encrypted
      add :secrets, :binary

      # Is the provider/service being currently active
      add :is_active, :boolean, default: false

      add :is_valid, :boolean, default: true

      # foreign key to provider id
      add :provider_id, references(:providers, on_delete: :nilify_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:credentials, [:provider_id, :organization_id])
  end

  defp chatbase_jobs do
    create table(:chatbase_jobs) do
      # references the last message we processed
      add :message_id, references(:messages, on_delete: :nilify_all), null: true

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chatbase_jobs, :organization_id)
    create unique_index(:chatbase_jobs, :message_id)
  end
end
