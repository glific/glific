defmodule Glific.Repo.Migrations.DropRegistrationsTable do
  @moduledoc """
  Drops the registrations table, superseded by the ERP-first onboarding flow.

  down/0 is a no-op rather than recreating an empty table — it stays reversible so a
  rollback isn't blocked, and up/0 uses drop_if_exists so re-migrating after one is safe.
  """

  use Ecto.Migration

  def up do
    drop_if_exists table(:registrations)
  end

  def down, do: :ok
end
