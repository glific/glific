defmodule Glific.Repo.Migrations.CreateTopic do
  use Ecto.Migration

  def change do
    alter table(:flow_labels) do
      add(:type, :string,
        comment: "Flow label type for now can be flow or ticket"
      )
    end
  end
end
