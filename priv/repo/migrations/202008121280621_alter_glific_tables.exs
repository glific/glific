defmodule Glific.Repo.Migrations.AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  Alter Glific tables
  """

  def up do
    alter table(:messages) do
      # Message uuid, primarly needed for flow editor
      add :uuid, :uuid, null: true
    end

    alter table(:groups) do
      # Description of the group
      add :description, :string, null: true
    end

    alter table(:flows) do
      # Enable ignore keywords while in the flow
      add :ignore_keywords, :boolean, default: false
    end

    # List of global keywords to trigger the flow
    create table(:flow_global_keywords) do
      add :name, :string, null: false

      add :flow_id, references(:flows, on_delete: :delete_all), null: false
    end

    create unique_index(:flow_global_keywords, :name)
  end
end
