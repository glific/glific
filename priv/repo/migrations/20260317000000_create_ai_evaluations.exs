defmodule Glific.Repo.Migrations.CreateAIEvaluations do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TYPE ai_evaluation_status_enum AS ENUM (
      'create_in_progress',
      'processing',
      'failed',
      'completed'
    )
    """)

    create table(:ai_evaluations) do
      add :name, :string, null: false
      add :status, :ai_evaluation_status_enum, null: false, default: "create_in_progress"
      add :failure_reason, :string
      add :results, :map, default: %{}
      add :kaapi_evaluation_id, :integer
      add :dataset_id, :integer, null: false

      add :assistant_config_version_id,
          references(:assistant_config_versions, on_delete: :nilify_all)

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create index(:ai_evaluations, [:organization_id])
    create index(:ai_evaluations, [:status])
    create index(:ai_evaluations, [:assistant_config_version_id])
  end

  def down do
    drop table(:ai_evaluations)
    execute("DROP TYPE IF EXISTS ai_evaluation_status_enum")
  end
end
