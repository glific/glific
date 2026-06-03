defmodule Glific.Repo.Migrations.FixAssistantActiveConfigVersionFk do
  use Ecto.Migration

  def up do
    drop_if_exists constraint(:assistants, :assistants_active_config_version_id_fkey)

    alter table(:assistants) do
      modify :active_config_version_id,
             references(:assistant_config_versions, on_delete: :nilify_all),
             null: true
    end
  end

  def down do
    drop_if_exists constraint(:assistants, :assistants_active_config_version_id_fkey)

    alter table(:assistants) do
      modify :active_config_version_id,
             references(:assistant_config_versions, on_delete: :nothing),
             null: true
    end
  end
end
