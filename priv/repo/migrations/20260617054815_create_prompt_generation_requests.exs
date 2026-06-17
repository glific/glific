defmodule Glific.Repo.Migrations.CreatePromptGenerationRequests do
  use Ecto.Migration

  def change do
    create table(:prompt_generation_requests) do
      add :inputs, :jsonb,
        null: false,
        comment: "The 9 NGO answers used to generate the prompt (keyed by field name)"

      add :generated_prompt, :text,
        comment: "The LLM-generated system prompt; nil until status is ready"

      add :status, :string,
        null: false,
        default: "in_progress",
        comment: "Lifecycle status: in_progress | ready | failed"

      add :kaapi_job_id, :string,
        comment: "Async job ID returned by Kaapi; used to match the callback"

      add :error_message, :text, comment: "Error detail from Kaapi callback when status is failed"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      add :user_id, references(:users, on_delete: :nilify_all),
        comment: "User who initiated the generation request; nullable"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:prompt_generation_requests, [:kaapi_job_id])
    create index(:prompt_generation_requests, [:organization_id])
  end
end
