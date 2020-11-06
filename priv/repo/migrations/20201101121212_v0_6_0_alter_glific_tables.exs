defmodule Glific.Repo.Migrations.V0_6_0_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.6.0 Alter Glific tables
  """

  alias Glific.{
    Flows.FlowContext,
    Flows.FlowCount,
    Flows.FlowRevision,
    Messages.Message,
    Messages.MessageMedia,
    Repo
  }

  import Ecto.Query, warn: false

  def change do
    flow_results()

    flow_revisions()

    messages()

    add_organization_id()
  end

  defp flow_revisions do
    alter table(:flow_revisions) do
      add :version, :integer, default: 0
    end
  end

  defp flow_results do
    # Create a table to store the values for a specific flow at a specific point in time
    # This is typically useful in a quiz scenario where we are collecting answers for different
    # questions across time
    create table(:flow_results) do
      # This is a key value map of the results saved during this flow run
      add :results, :map, default: %{}

      add :contact_id, references(:contacts, on_delete: :delete_all), null: false

      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      # We store flows with both id and uuid, since floweditor always refers to a flow by its uuid
      add :flow_uuid, :uuid, null: false

      # which specific published version are we referring to. This allows us to narrow
      # down the questions
      add :flow_version, :integer, default: 1, null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_results, [:contact_id, :flow_id, :flow_version])
    create index(:flow_results, [:contact_id, :organization_id])
  end

  defp messages do
    alter table(:messages) do
      # it will be null for regular messages
      add :flow_id, references(:flows, on_delete: :nilify_all), null: true
    end
  end

  defp add_organization_id do
    # foreign key to organization restricting scope of this table to this organization only
    # keeping the field nullable so that migration can run with production data

    alter table(:flow_contexts) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    alter table(:flow_counts) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    alter table(:flow_revisions) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    alter table(:messages_media) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    # Flush and update organization id of existing data
    flush()
    update_org_id_of_flow_tables()
    update_org_id_of_message_media()

    # Modify the field to not nullable
    alter table(:flow_contexts) do
      modify :organization_id, :bigint, null: false
    end

    alter table(:flow_counts) do
      modify :organization_id, :bigint, null: false
    end

    alter table(:flow_revisions) do
      modify :organization_id, :bigint, null: false
    end

    alter table(:messages_media) do
      modify :organization_id, :bigint, null: false
    end
  end

  defp update_org_id_of_flow_tables do
    from([fc] in FlowContext,
      join: f in assoc(fc, :flow),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Glific.Repo.update_all([])

    from([fc] in FlowCount,
      join: f in assoc(fc, :flow),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Glific.Repo.update_all([])

    from([fc] in FlowRevision,
      join: f in assoc(fc, :flow),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Glific.Repo.update_all([])
  end

  defp update_org_id_of_message_media do
    # update organization_id of all message media entries
    messages =
      Message
      |> where([m], not is_nil(m.media_id))
      |> preload(:media)
      |> Repo.all()

    messages
    |> Enum.each(fn message ->
      from([mm] in MessageMedia,
        where: mm.id == ^message.media_id,
        update: [set: [organization_id: ^message.organization_id]]
      )
      |> Repo.update_all([])
    end)

    # Fix for seeds of message_media without a message
    from([mm] in MessageMedia,
      where: is_nil(mm.organization_id),
      update: [set: [organization_id: 1]]
    )
    |> Repo.update_all([])
  end
end
