defmodule Glific.Repo.Migrations.AddFeedbackToAiMessages do
  use Ecto.Migration

  def change do
    alter table(:ai_messages) do
      add :feedback, :string, comment: "User feedback on this answer: like | dislike | null"
    end

    create constraint(:ai_messages, :feedback_must_be_like_or_dislike,
             check: "feedback IN ('like', 'dislike')"
           )
  end
end
