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

    alter table(:users) do
      add :contact_id, references(:contacts, on_delete: :nilify_all), null: false
    end

    create unique_index(:users, :contact_id)

    alter table(:organizations) do
      add :out_of_office, :map, default: %{enabled: false}
    end

    alter_flow_tables()
  end

  def alter_flow_tables do
    alter table(:flows) do
      # Enable ignore keywords while in the flow
      add :ignore_keywords, :boolean, default: false

      # List of keywords to trigger the flow
      add :keywords, {:array, :string}, default: []
    end

    alter table(:flow_contexts) do
      # Add list of recent messages for both inbound and outbound
      # for outbound we store the uuid
      add :recent_inbound, :jsonb, default: "[]"
      add :recent_outbound, :jsonb, default: "[]"
    end

    alter table(:flow_revisions) do
      # Status of flow revision draft or done
      add :status, :string, default: "draft"
    end
  end
end
