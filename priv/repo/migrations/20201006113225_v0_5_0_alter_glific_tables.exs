defmodule Glific.Repo.Migrations.V0_5_0_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.5.0 Alter Glific tables
  """

  def change do
    credentials()

    organizations()

    contacts()

    messages()
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

  defp credentials do
    drop constraint(:credentials, :credentials_provider_id_fkey)

    alter table(:credentials) do
      # foreign key to provider id
      modify :provider_id, references(:providers, on_delete: :nothing), null: false
    end
  end

  defp contacts do
    alter table(:contacts) do
      remove :provider_status
      add :bsp_status, :contact_provider_status_enum, null: false, default: "none"
    end
  end

  defp messages do
    # using microsecond for correct ordering of messages
    alter table(:messages) do
      remove :provider_status
      remove :provider_message_id
      add :bsp_status, :message_status_enum
      add :bsp_message_id, :string, null: true
    end
  end
end
