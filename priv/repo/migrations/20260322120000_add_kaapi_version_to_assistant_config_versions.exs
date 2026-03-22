defmodule Glific.Repo.Migrations.AddKaapiVersionToAssistantConfigVersions do
  use Ecto.Migration

  def change do
    alter table(:assistant_config_versions) do
      add(:kaapi_version, :integer)
    end
  end
end
