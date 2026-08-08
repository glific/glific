defmodule Glific.Repo.Migrations.CreateTemplateRephraseRequests do
  use Ecto.Migration

  def change do
    create table(:template_rephrase_requests) do
      add :original_text, :text,
        null: false,
        comment: "The WhatsApp template body text submitted for rephrasing"

      add :action, :string,
        null: false,
        comment: "Rephrase action: professional | utility | custom"

      add :custom_prompt, :text,
        comment: "Free-text rephrase instruction; present only when action is custom"

      add :rephrased_text, :text,
        comment: "The LLM-rephrased template body; nil until status is ready"

      add :status, :string,
        null: false,
        default: "in_progress",
        comment: "Lifecycle status: in_progress | ready | failed"

      add :request_id, :string,
        null: false,
        comment:
          "Correlation id we send to Kaapi in request_metadata; echoed back in the callback metadata"

      add :error_message, :text, comment: "Error detail from Kaapi callback when status is failed"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      add :user_id, references(:users, on_delete: :nilify_all),
        comment: "User who initiated the rephrase request; nullable"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:template_rephrase_requests, [:request_id, :organization_id],
             name: :template_rephrase_requests_request_id_organization_id_index
           )

    create index(:template_rephrase_requests, [:organization_id])
    create index(:template_rephrase_requests, [:user_id])
  end
end
