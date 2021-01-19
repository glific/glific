defmodule Glific.Repo.Migrations.V0_5_0_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.5.0 Alter Glific tables
  """

  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    credentials()

    organizations()

    contacts()

    messages()

    providers()
  end

  defp organizations do
    drop unique_index(:organizations, :provider_phone)

    alter table(:organizations) do
      remove :provider_appname
      remove :provider_phone
      remove :provider_limit
    end

    rename table(:organizations), :provider_id, to: :bsp_id
  end

  defp credentials do
    drop constraint(:credentials, :credentials_provider_id_fkey)

    alter table(:credentials) do
      # foreign key to provider id
      modify :provider_id, references(:providers, on_delete: :nothing, prefix: @global_schema),
        null: false
    end
  end

  defp contacts do
    rename table(:contacts), :provider_status, to: :bsp_status
  end

  defp messages do
    rename table(:messages), :provider_status, to: :bsp_status
    rename table(:messages), :provider_message_id, to: :bsp_message_id
  end

  defp providers do
    alter table("providers", prefix: @global_schema) do
      add :description, :string
    end
  end
end
