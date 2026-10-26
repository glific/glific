defmodule Glific.Repo.Migrations.DropOrganizationEvalRequestsTable do
  @moduledoc """
  Drops the organization_eval_requests table; AI Evaluations are now enabled for every
  organization, so the access-request flow is gone.

  down/0 is a no-op rather than recreating an empty table so a rollback isn't blocked.
  """

  use Ecto.Migration

  def up do
    drop_if_exists table(:organization_eval_requests)
  end

  def down, do: :ok
end
