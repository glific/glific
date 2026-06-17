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

      add :request_id, :string,
        null: false,
        comment:
          "Correlation id we send to Kaapi in request_metadata; echoed back in the callback metadata"

      add :kaapi_job_id, :string,
        comment: "Async job id from the Kaapi sync ack (informational; not the callback key)"

      add :error_message, :text, comment: "Error detail from Kaapi callback when status is failed"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      add :user_id, references(:users, on_delete: :nilify_all),
        comment: "User who initiated the generation request; nullable"

      # microsecond precision so dispatch->callback latency (tracked in AppSignal) is accurate to ms
      timestamps(type: :utc_datetime_usec)
    end

    # Org-scoped uniqueness on request_id — this is the real callback correlation key.
    # Kaapi echoes it back as metadata.request_id in the async callback body.
    create unique_index(:prompt_generation_requests, [:request_id, :organization_id],
             name: :prompt_generation_requests_request_id_organization_id_index
           )

    create index(:prompt_generation_requests, [:organization_id])
  end
end
