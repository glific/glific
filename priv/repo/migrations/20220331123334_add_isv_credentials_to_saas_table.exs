defmodule Glific.Repo.Migrations.AddISVCredentialsToSaasTable do
  use Ecto.Migration

  def change do
    add_json()
  end

  defp add_json do
    alter table(:saas) do
      add :isv_credentials, :map, default: %{}
    end
  end
end
