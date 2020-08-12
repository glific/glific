defmodule Glific.Repo.Migrations.AlterMessageTableForUUID do
  use Ecto.Migration
  @moduledoc """
  Alter messages table with uuid field
  """

  def up do
    alter table(:messages) do
      # Message uuid, primarly needed for flow editor
      add :uuid, :uuid, null: true
    end
  end
end
