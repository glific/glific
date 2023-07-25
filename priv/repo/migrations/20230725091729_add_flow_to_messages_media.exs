defmodule Glific.Repo.Migrations.AddFlowToMessagesMedia do
  use Ecto.Migration

  def up do
    alter table(:messages_media) do
      add(:flow, :string)
    end

  end

  def down do
    alter table(:messages_media) do
      remove(:flow)
    end
  end
end
