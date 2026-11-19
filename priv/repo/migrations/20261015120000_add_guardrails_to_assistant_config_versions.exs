defmodule Glific.Repo.Migrations.AddGuardrailsToAssistantConfigVersions do
  use Ecto.Migration

  def change do
    alter table(:assistant_config_versions) do
      add :input_guardrails, :map,
        default: "[]",
        null: false,
        comment:
          "JSON array of inline guardrail validator specs run on the user input before the LLM call"

      add :output_guardrails, :map,
        default: "[]",
        null: false,
        comment:
          "JSON array of inline guardrail validator specs run on the LLM output before it is returned"
    end
  end
end
