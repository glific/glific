defmodule Glific.Repo.Migrations.DropOrganizationEvalRequestsTable do
  use Ecto.Migration

  def up do
    drop_if_exists table(:organization_eval_requests)
  end

  # no-op: the access-request feature is gone, recreating an empty table would only block rollback
  def down, do: :ok
end
