defmodule Glific.Repo.Migrations.TrackSendToGroup do
  use Ecto.Migration

  def change do
    messages()

    flow_contexts()
  end

  def messages do
    alter table(:messages) do
      add :group_message_id, references(:messages, on_delete: :nilify_all),
        null: true,
        comment: "If this message was sent to a group, link the two"
    end

    create_if_not_exists index(:messages, :group_message_id, where: "group_message_id IS NOT NULL")
  end

  def flow_contexts do
    alter table(:flow_contexts) do
      add :group_message_id, references(:messages, on_delete: :nilify_all),
        null: true,
        comment: "If this message was sent to a group, link the two"
    end

    create_if_not_exists index(:flow_contexts, :group_message_id,
                           where: "group_message_id IS NOT NULL"
                         )
  end
end
