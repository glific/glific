defmodule Glific.Repo.Migrations.CreateFlowLabelTable do
  use Ecto.Migration

  def change do
    flow_labels()
    add_flow_lable_to_message()
  end

  @doc """
  Create flow label to associate flow messages with label
  """
  def flow_labels do
    create table(:flow_labels) do
      add :uuid, :uuid, null: false, comment: "Unique ID for each flow label"
      add :name, :string, comment: "Name/tag of the flow label"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_labels, [:name, :organization_id])
  end

  def add_flow_lable_to_message() do
    alter table(:messages) do
      # The body of the message
      add :flow_label, :string, null: true, comment: "Tagged flow label for the message"
    end
  end
end
