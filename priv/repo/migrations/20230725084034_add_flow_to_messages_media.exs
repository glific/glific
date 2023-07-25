defmodule Glific.Repo.Migrations.AddFlowToMessagesMedia do
  use Ecto.Migration

  def up do
    alter table(:messages_media) do
      add(:flow, :string)
    end

    execute("ALTER TABLE messages_media ADD CONSTRAINT valid_flow CHECK (flow IN ('inbound', 'outbound'))")
  end

  def down do
    execute("ALTER TABLE messages_media DROP CONSTRAINT valid_flow")
    alter table(:messages_media) do
      remove(:flow)
    end
  end
end
