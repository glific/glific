defmodule Glific.Repo.Migrations.OrganizationNewcontactFlowId do
  use Ecto.Migration

  def change do
    organization_newcontact_flow_id()
  end

  defp organization_newcontact_flow_id() do
    alter table(:organizations) do
      add :newcontact_flow_id, references(:flows, on_delete: :nilify_all),
        null: true,
        comment: "Flow which will trigger when newcontact joins the bot"
    end
  end
end
