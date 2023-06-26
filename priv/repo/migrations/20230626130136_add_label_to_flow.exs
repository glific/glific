defmodule Glific.Repo.Migrations.AddLabelToFlow do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add(:labels, {:array, :string}, default: [], comment: "Labels to identify the flow")
    end
  end

end
