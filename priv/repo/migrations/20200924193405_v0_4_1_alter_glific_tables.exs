defmodule Glific.Repo.Migrations.V041AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.4.1 Alter Glific tables
  """

  def change do
    credentials()

    providers()

    organizations()

    chatbase_jobs()

    messages()

    contacts()
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

  defp organizations do
    drop unique_index(:organizations, :provider_phone)

    alter table("organizations") do
      remove :provider_id
      add :bsp_id, references(:providers, on_delete: :nothing), null: false

      remove :provider_appname
      remove :provider_phone
      remove :provider_limit
    end
  end

  defp contacts do
    alter table(:contacts) do
      remove :provider_status
      add :bsp_status, :contact_bsp_status_enum, null: false, default: "none"
    end
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
      add :provider_id, references(:providers, on_delete: :nothing), null: false

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

  defp messages do
    # using microsecond for correct ordering of messages
    alter table(:messages) do
      modify :inserted_at, :utc_datetime_usec
      modify :updated_at, :utc_datetime_usec
    end
  end
end
