defmodule Glific.Repo.Migrations.V160_AlterGlificTables do
  use Ecto.Migration

  def change do
    notifications()
  end

  defp notifications do
    alter table(:notifications) do
      add :is_read, :boolean,
        default: false,
        comment: "Has the user read the notifications."
    end
  end
end
