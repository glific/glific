defmodule Glific.Repo.Migrations.AddKaapiUuidToAssistants do
  use Ecto.Migration

  def up do
    alter table(:assistants) do
      add_if_not_exists :kaapi_uuid, :string, null: true, comment: "Kaapi UUID for the config"

      add_if_not_exists :active_config_version_id,
                        references(:assistant_config_versions, on_delete: :nilify_all),
                        comment: "Reference to the currently active configuration version"
    end

    # Remove kaapi_uuid from assistant_config_versions if it was added there by mistake
    alter table(:assistant_config_versions) do
      remove_if_exists :kaapi_uuid, :string
    end

    create_if_not_exists index(:assistants, [:active_config_version_id])
  end

  def down do
    drop_if_exists index(:assistants, [:active_config_version_id])
    drop_if_exists constraint(:assistants, :assistants_active_config_version_id_fkey)

    alter table(:assistants) do
      remove_if_exists :active_config_version_id, :bigint
      remove_if_exists :kaapi_uuid, :string
    end
  end
end
