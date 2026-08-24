defmodule GlificWeb.Schema.AIEvaluationTypes do
  @moduledoc """
  GraphQL Representation of Glific's AI Evaluation DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.{Authorize, RequireFeatureFlag}

  object :result_error do
    field :message, non_null(:string)
  end

  object :ai_eval_golden_qa do
    field :id, :id
    field :name, :string
    field :duplication_factor, :integer
  end

  object :ai_eval_assistant do
    field :id, :id
    field :name, :string
  end

  object :ai_eval_config_version do
    field :id, :id
    field :version_number, :integer
    field :assistant, :ai_eval_assistant
  end

  object :ai_evaluation do
    field :id, :id
    field :name, :string
    field :status, :ai_evaluation_status_enum
    field :failure_reason, :string
    field :results, :json
    field :duplication_factor, :integer
    field :golden_qa, :ai_eval_golden_qa
    field :assistant_config_version, :ai_eval_config_version
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :golden_qa_item do
    field :id, :id
    field :name, :string
    field :golden_qa_id, :id
    field :duplication_factor, :integer
    field :file_name, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  input_object :ai_evaluation_filter do
    field :name, :string
  end

  input_object :golden_qa_filter do
    field :name, :string
  end

  input_object :golden_qa_input do
    field :name, non_null(:string)
    field :file, non_null(:upload)
    field :duplication_factor, non_null(:integer)
  end

  object :golden_qa do
    field :id, :id
    field :name, :string
    field :duplication_factor, :integer
    field :dataset_id, :integer
    field :file_name, :string
    field :signed_url, :string
    field :total_items, :integer
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :golden_qa_result do
    field :golden_qa, :golden_qa
    field :errors, list_of(:result_error)
  end

  object :evaluation_result do
    field :evaluation, :create_evaluation_result
    field :errors, list_of(:input_error)
  end

  object :create_evaluation_result do
    field :status, :ai_evaluation_status_enum
  end

  input_object :evaluation_input do
    field :golden_qa_id, non_null(:id)
    field :evaluation_name, non_null(:string)
    field :config_id, non_null(:id)
    field :duplication_factor, :integer, default_value: 1
  end

  object :evaluation_scores_result do
    field :scores, :json
    field :errors, list_of(:result_error)
  end

  object :kaapi_model do
    field :provider, :string
    field :model_name, :string
    field :completion_type, list_of(:string)
    field :config, :json
    field :input_modalities, list_of(:string)
    field :output_modalities, list_of(:string)
    field :pricing, :json
  end

  object :improve_prompt do
    field :status, :string
  end

  object :improve_prompt_result do
    field :improve_prompt, :improve_prompt
    field :errors, list_of(:result_error)
  end

  object :improve_prompt_update do
    field :status, :string
    field :config_version, :assistant_config_version
    field :error, :string
  end

  object :ai_evaluation_queries do
    @desc "List AI Evaluations"
    field :ai_evaluations, list_of(:ai_evaluation) do
      arg(:filter, :ai_evaluation_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.list_ai_evaluations/3)
    end

    @desc "Count AI Evaluations"
    field :count_ai_evaluations, :integer do
      arg(:filter, :ai_evaluation_filter)
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.count_ai_evaluations/3)
    end

    @desc "List Golden QAs"
    field :golden_qas, list_of(:golden_qa_item) do
      arg(:filter, :golden_qa_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.list_golden_qas/3)
    end

    @desc "Count Golden QAs"
    field :count_golden_qas, :integer do
      arg(:filter, :golden_qa_filter)
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.count_golden_qas/3)
    end

    @desc "Get Evaluation Scores"
    field :evaluation_scores, :evaluation_scores_result do
      arg(:id, non_null(:id))
      arg(:export_format, :string)
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.get_evaluation_scores/3)
    end

    @desc "Get Golden QA"
    field :golden_qa, :golden_qa_result do
      arg(:id, non_null(:id))
      arg(:include_signed_url, :boolean, default_value: false)
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.get_golden_qa/3)
    end

    @desc "Get the organization's AI Evaluations access request status"
    field :org_eval_access_request, :org_eval_access_request do
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.get_org_eval_access_request/3)
    end

    @desc "List active Kaapi models (openai only, for now)"
    field :kaapi_models, list_of(:kaapi_model) do
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.list_kaapi_models/3)
    end
  end

  object :org_eval_access_request do
    field :status, :string
  end

  object :request_eval_access_result do
    field :status, :string
    field :errors, list_of(:result_error)
  end

  object :ai_evaluation_mutations do
    @desc "Request access to the AI Evaluations feature"
    field :request_ai_evaluation_access, :request_eval_access_result do
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.request_ai_evaluation_access/3)
    end

    @desc "Create Golden QA"
    field :create_golden_qa, :golden_qa_result do
      arg(:input, non_null(:golden_qa_input))
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.create_golden_qa/3)
    end

    @desc "Create AI Evaluation"
    field :create_evaluation, :evaluation_result do
      arg(:input, non_null(:evaluation_input))
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      resolve(&Resolvers.AIEvaluations.create_evaluation/3)
    end

    @desc "Request a v2 (native-judge) prompt improvement for a completed evaluation"
    field :improve_evaluation_prompt, :improve_prompt_result do
      arg(:evaluation_id, non_null(:id))
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      middleware(RequireFeatureFlag, {:is_ai_evaluation_enabled, "AI Evaluation V2"})
      resolve(&Resolvers.AIEvaluations.improve_evaluation_prompt/3)
    end
  end

  object :ai_evaluation_subscriptions do
    @desc "Delivers the result of a v2 prompt-improvement request once Kaapi's callback arrives."
    field :improve_prompt_updated, :improve_prompt_update do
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})
      middleware(RequireFeatureFlag, {:is_ai_evaluation_enabled, "AI Evaluation V2"})

      config(fn _args, %{context: %{current_user: user}} ->
        {:ok, topic: "#{user.organization_id}"}
      end)
    end

    @desc "Delivers an AI evaluation's status as it changes (e.g. once Kaapi's run completes)."
    field :ai_evaluation_updated, :ai_evaluation do
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:ai_evaluations, "AI Evaluations"})

      config(fn _args, %{context: %{current_user: user}} ->
        {:ok, topic: "#{user.organization_id}"}
      end)
    end
  end
end
