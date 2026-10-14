defmodule Glific.Repo.Migrations.CreateLlmCalls do
  use Ecto.Migration

  def change do
    create table(:llm_calls,
             comment: "One row per Kaapi LLM call made from a flow, recorded on its callback"
           ) do
      add :success, :boolean, comment: "Whether Kaapi reported the call as successful"
      add :error, :text, comment: "Error message returned by Kaapi on failure"

      add :provider_response_id, :string, comment: "Response id assigned by the LLM provider"
      add :conversation_id, :string, comment: "Kaapi conversation (thread) id"
      add :provider, :string, comment: "LLM provider, e.g. openai-native"
      add :model, :string, comment: "Model that served the call"

      add :input_from_user, :text, comment: "Raw input sent by the contact"

      add :input_to_llm, :text,
        comment: "Input actually sent to the LLM, after the input guardrail ran"

      add :output_from_llm, :text, comment: "Raw text output returned by the LLM"

      add :output_to_user, :text,
        comment: "Output handed back to the flow, after the output guardrail ran"

      add :input_guardrail, :map,
        comment: "Validators the input guardrail ran, from the callback metadata"

      add :output_guardrail, :map,
        comment: "Validators the output guardrail ran, from the callback metadata"

      add :tokens, :map,
        comment: "Token usage from the callback: input, output, total and reasoning tokens"

      add :flow_id, references(:flows, on_delete: :nilify_all), comment: "Flow that made the call"

      add :contact_id, references(:contacts, on_delete: :nilify_all),
        comment: "Contact the call was made for"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      timestamps(type: :utc_datetime)
    end

    create index(:llm_calls, [:organization_id, :inserted_at])
    create index(:llm_calls, [:flow_id])
    create index(:llm_calls, [:contact_id])
  end
end
