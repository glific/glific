defmodule Glific.Repo.Migrations.CreateFlowEditorTables do
  use Ecto.Migration

  def change do
    flows()
    flow_revision()
  end

  def flows do
    create table(:flows, primary_key: false) do
      add :uuid, :uuid, primary_key: true
      add :name, :string, null: false

      add :version_number, :string, default: "13.1.0"

      add :language_id, :bigint

      add :flow_type, :string, default: "message"

      timestamps(type: :utc_datetime)
    end
  end

  def flow_revision do
    create table(:flow_revisions, primary_key: false) do
      add :uuid, :uuid, primary_key: true
      add :definition, :map
      add :flow_uuid, :uuid
      add :revision_number, :integer
      timestamps(type: :utc_datetime)
    end
  end
end
