defmodule Glific.Questions.QuestionsQuestionSets do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__
  alias Glific.{Questions.Question, Questions.QuestionSet}

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          question_id: non_neg_integer | nil,
          question_sets_id: non_neg_integer | nil,
          question: Question.t() | Ecto.Association.NotLoaded.t() | nil,
          question_set: QuestionSet.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :question_id,
    :question_sets_id
  ]
  @optional_fields [
    :number_questions_right
  ]

  schema "questions_question_sets" do
    belongs_to :question, Question

    belongs_to :question_set, QuestionSet

    field :question_sets_id, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(QuestionsQuestionSets.t(), map()) :: Ecto.Changeset.t()
  def changeset(questions_question_sets, attrs) do
    questions_question_sets
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
