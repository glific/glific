defmodule Glific.Questions.QuestionsAnswers do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{Contacts.Contact, Messages.Message, Questions.Question, Questions.QuestionSet}

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact_id: non_neg_integer | nil,
          message_id: non_neg_integer | nil,
          question_id: non_neg_integer | nil,
          question_set_id: non_neg_integer | nil,
          answer: String.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          message: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          question: Question.t() | Ecto.Association.NotLoaded.t() | nil,
          question_set: QuestionSet.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :contact_id,
    :message_id,
    :question_id,
    :question_set_id,
    :answer
  ]
  @optional_fields []

  schema "questions_answers" do
    belongs_to :contact, Contact
    belongs_to :message, Message
    belongs_to :question, Question
    belongs_to :question_set, QuestionSet

    field :answer, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(QuestionsAnswers.t(), map()) :: Ecto.Changeset.t()
  def changeset(questions_answers, attrs) do
    questions_answers
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
