defmodule Glific.Questions.QuestionSet do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          number_questions_right: integer() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :label
  ]
  @optional_fields [
    :number_questions_right
  ]

  schema "question_sets" do
    field :label, :string

    field :number_questions_right, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(QuestionSet.t(), map()) :: Ecto.Changeset.t()
  def changeset(question_set, attrs) do
    question_set
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
