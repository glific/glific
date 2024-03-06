defmodule Glific.Repo.Migrations.AddWaGroupIdToTrigger do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :group_type, :string, comment: "one of WABA, WA"
    end

    alter table(:groups) do
      add :group_type, :string, default: "WABA", comment: "one of WABA, WA"
    end
  end
end
