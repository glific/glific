defmodule GlificWeb.Schema.AIEvaluationTypes do
  @moduledoc """
  GraphQL Representation of Glific's AI Evaluation DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.{Authorize, RequireFeatureFlag}

  input_object :golden_qa_input do
    field :name, non_null(:string)
    field :file, non_null(:upload)
    field :duplication_factor, non_null(:integer)
  end

  object :golden_qa do
    field :name, :string
  end

  object :evaluation_result do
    field :status, :string
    field :errors, list_of(:input_error)
  end

  input_object :evaluation_input do
    field :dataset_id, non_null(:id)
    field :experiment_name, non_null(:string)
    field :config_id, non_null(:id)
    field :config_version, non_null(:id)
  end

  object :golden_qa_result do
    field :golden_qa, :golden_qa
    field :errors, list_of(:input_error)
  end

  object :ai_evaluation_mutations do
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
  end
end
