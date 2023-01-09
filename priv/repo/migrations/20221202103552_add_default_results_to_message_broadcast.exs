defmodule Glific.Repo.Migrations.AddDefaultResultsToMessageBroadcast do
  use Ecto.Migration

  def change do
    alter table(:message_broadcasts) do
      add(:default_results, :jsonb, comment: "Default results are required for the flow")
    end
  end
end
