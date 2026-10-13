defmodule GlificWeb.Schema.GuardrailTypes do
  @moduledoc """
  GraphQL Representation of Kaapi guardrail validator configs
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
    field :errors, list_of(:result_error)
  end

  object :guardrail_config do
    field :id, :id
    field :name, :string
    field :type, :string

    @desc "One of: input, output"
    field :stage, :string

    @desc "One of: exception, fix, rephrase"
    field :on_fail_action, :string
    field :is_enabled, :boolean

    @desc "Validator-specific config, as described by the validator's JSON schema"
    field :config, :json
    field :inserted_at, :string
    field :updated_at, :string
  end

  object :guardrail_config_result do
    field :guardrail_config, :guardrail_config
    field :errors, list_of(:result_error)
  end

  object :guardrail_configs_result do
    field :guardrail_configs, list_of(:guardrail_config)
    field :errors, list_of(:result_error)
  end

  input_object :guardrail_config_filter do
    field :ids, list_of(:id)
    field :stage, :string
    field :type, :string
  end

  input_object :guardrail_config_input do
    field :name, non_null(:string)
    field :type, non_null(:string)
    field :stage, non_null(:string)
    field :on_fail_action, :string
    field :is_enabled, :boolean

    @desc "Validator-specific config, as described by the validator's JSON schema"
    field :config, :json
  end

  input_object :guardrail_config_update_input do
    field :name, :string
    field :type, :string
    field :stage, :string
    field :on_fail_action, :string
    field :is_enabled, :boolean
  end

  object :guardrail_queries do
    @desc "List guardrail validator types and their config JSON schemas"
    field :guardrail_validators, :guardrail_validators_result do
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:is_ai_guardrail_enabled, "AI Guardrails"})
      resolve(&Resolvers.Guardrails.list_guardrail_validators/3)
    end

    @desc "List guardrail validator configs"
    field :guardrail_configs, :guardrail_configs_result do
      arg(:filter, :guardrail_config_filter)
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:is_ai_guardrail_enabled, "AI Guardrails"})
      resolve(&Resolvers.Guardrails.list_guardrail_configs/3)
    end

    @desc "Get a guardrail validator config"
    field :guardrail_config, :guardrail_config_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:is_ai_guardrail_enabled, "AI Guardrails"})
      resolve(&Resolvers.Guardrails.get_guardrail_config/3)
    end
  end

  object :guardrail_mutations do
    @desc "Create a guardrail validator config"
    field :create_guardrail_config, :guardrail_config_result do
      arg(:input, non_null(:guardrail_config_input))
      middleware(Authorize, :manager)
      middleware(RequireFeatureFlag, {:is_ai_guardrail_enabled, "AI Guardrails"})
      resolve(&Resolvers.Guardrails.create_guardrail_config/3)
    end

    @desc "Update a guardrail validator config"
    field :update_guardrail_config, :guardrail_config_result do
      arg(:id, non_null(:id))
      arg(:input, non_null(:guardrail_config_update_input))
      middleware(Authorize, :manager)
      middleware(RequireFeatureFlag, {:is_ai_guardrail_enabled, "AI Guardrails"})
      resolve(&Resolvers.Guardrails.update_guardrail_config/3)
    end

    @desc "Delete a guardrail validator config"
    field :delete_guardrail_config, :guardrail_config_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      middleware(RequireFeatureFlag, {:is_ai_guardrail_enabled, "AI Guardrails"})
      resolve(&Resolvers.Guardrails.delete_guardrail_config/3)
    end
  end
end
