defmodule Glific.AIEvaluations.AIEvaluation do
  @moduledoc """
  Schema for AI Evaluations created via Kaapi.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    AIEvaluations.AIEvaluation,
    Assistants.AssistantConfigVersion,
    Enums.AIEvaluationStatus,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t() | nil,
          status: AIEvaluationStatus.t(),
          failure_reason: String.t() | nil,
          results: map(),
          kaapi_evaluation_id: non_neg_integer() | nil,
          dataset_id: non_neg_integer() | nil,
          organization_id: non_neg_integer() | nil,
          assistant_config_version_id: non_neg_integer() | nil,
          assistant_config_version:
            AssistantConfigVersion.t() | Ecto.Association.NotLoaded.t() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :name,
    :status,
    :organization_id,
    :dataset_id
  ]

  @optional_fields [
    :failure_reason,
    :results,
    :kaapi_evaluation_id
  ]

  schema "ai_evaluations" do
    field(:name, :string)
    field(:status, AIEvaluationStatus, default: :create_in_progress)
    field(:failure_reason, :string)
    field(:results, :map, default: %{})
    field(:kaapi_evaluation_id, :integer)
    field(:dataset_id, :integer)
    belongs_to(:assistant_config_version, AssistantConfigVersion)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset for creating and updating AI evaluations.
  """
  @spec changeset(AIEvaluation.t(), map()) :: Ecto.Changeset.t()
  def changeset(evaluation, attrs) do
    evaluation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:organization)
  end
end
