defmodule Glific.Repo.Migrations.AddJsonToSaasTable do
  use Ecto.Migration

  def change do
    add_json()
  end

  defp add_json do
    alter table(:saas) do
      add :json, :map, default: %{}
    end
  end
end
