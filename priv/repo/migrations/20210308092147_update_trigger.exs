defmodule Glific.Repo.Migrations.UpdateTrigger do
  use Ecto.Migration

  def change do
    triggers()
  end

  defp triggers do
    alter table(:triggers) do
      remove :contact_id
    end
  end
end
