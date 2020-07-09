defmodule Glific.Repo.Migrations.CreateFlowEditorTables do
  use Ecto.Migration

  def change do
    flows()
    flow_revision()
  end

  def flows do
    create table(:flows) do
      add :name, :string, null: false

      # The language label in its default locale, e.g: हिंदी
      add :uuid, :string, null: false

      add :version_number, :string

      add :language, :string, default: "base"

      add :flow_type, :string, default: "message"

      timestamps(type: :utc_datetime)
    end
  end

  def flow_revision do
    create table(:flow_revisions) do
      add :definition, :map
      add :flow_id, references(:flows, on_delete: :nothing), null: false
      add :revision_number, :integer
      timestamps(type: :utc_datetime)
    end
  end
end
