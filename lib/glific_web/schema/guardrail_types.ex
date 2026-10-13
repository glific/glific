defmodule GlificWeb.Schema.GuardrailTypes do
  @moduledoc """
  GraphQL Representation of the Kaapi guardrail validator catalog
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.{Authorize, RequireFeatureFlag}

  object :guardrail_validator do
    field :type, :string

    @desc "JSON schema of the validator-specific config"
    field :config, :json
  end

  object :guardrail_validators_result do
    field :validators, list_of(:guardrail_validator)
  end

  object :guardrail_queries do
    @desc "List guardrail validator types and their config JSON schemas"
    field :guardrail_validators, :guardrail_validators_result do
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:is_ai_guardrail_enabled, "AI Guardrails"})
      resolve(&Resolvers.Guardrails.list_guardrail_validators/3)
    end
  end
end
