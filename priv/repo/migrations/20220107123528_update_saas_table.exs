defmodule Glific.Repo.Migrations.UpdateSaasTable do
  use Ecto.Migration

  def change do
    add_email_column()
  end

  defp add_email_column do
    alter table(:saas) do
      add :email, :string, comment: "Primary email address for the saas team."
    end
  end
end
