defmodule Glific.Questions.Question do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.Enums.QuestionType

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          shortcode: String.t() | nil,
          type: String.t() | nil,
          clean_answer: boolean() | false,
          strip_answer: boolean(),
          validate_answer: boolean() | Ecto.Association.NotLoaded.t() | nil,
          valid_answers: list() | [],
          number_retries: integer() | nil,
          shortcode_error: String.t() | nil,
          callback: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :label,
    :shortcode,
    :type
  ]
  @optional_fields [
    :clean_answer,
    :strip_answer,
    :validate_answer,
    :valid_answers,
    :shortcode_error,
    :callback
  ]

  schema "questions" do
    field :label, :string
    field :shortcode, :string
    field :type, QuestionType
    field :clean_answer, :boolean, default: false
    field :strip_answer, :boolean, default: false
    field :validate_answer, :boolean, default: false

    field :valid_answers, {:array, :integer}, default: []

    field :number_retries, :integer

    field :shortcode_error, :string

    field :callback, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Question.t(), map()) :: Ecto.Changeset.t()
  def changeset(question, attrs) do
    question
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
