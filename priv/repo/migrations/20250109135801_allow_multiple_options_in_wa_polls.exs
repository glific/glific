defmodule Glific.Repo.Migrations.AllowMultipleOptionsInWaPolls do
  use Ecto.Migration

  def change do
    alter table(:wa_polls) do
      add :allow_multiple_answer, :boolean,
        default: false,
        comment: "if users can select multiple answers in a WhatsApp poll or not"
    end
  end
end
