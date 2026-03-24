defmodule Glific.Repo.Migrations.AddKaapiVersionToAssistantConfigVersions do
  use Ecto.Migration

  def change do
    alter table(:assistant_config_versions) do
      add(:kaapi_version_number, :integer)
    end
  end
end
