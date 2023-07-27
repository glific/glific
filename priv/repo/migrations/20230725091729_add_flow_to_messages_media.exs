defmodule Glific.Repo.Migrations.AddFlowToMessagesMedia do
  use Ecto.Migration

  def up do
    alter table(:messages_media) do
      add(:flow, :message_flow_enum)
    end
  end

  def down do
    alter table(:messages_media) do
      remove(:flow)
    end
  end
end
