defmodule Glific.Repo.Migrations.OptinFlowId do
  use Ecto.Migration

  def change do
    organization_optin_flow_id()
  end

  defp organization_optin_flow_id() do
    alter table(:organizations) do
      add :optin_flow_id, references(:flows, on_delete: :nilify_all),
        null: true,
        comment: "Flow which will trigger for contact to optin"
    end
  end
end
