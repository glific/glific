defmodule Glific.Repo.Migrations.AddMessageContext do
  use Ecto.Migration

  def change do
    messages()
  end

  def messages do
    alter table(:messages) do
      add :bsp_context_id, :text, comment: "If this message was a reply to a previous message, link the two"
      add :bsp_context_message_id, references(:messages, on_delete: :delete_all), null: true
    end
  end
end
