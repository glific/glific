defmodule Glific.Repo.Migrations.AddLabelsToFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add(:labels, :string, default: "", comment: "Labels to identify the flow")
    end
  end
end
