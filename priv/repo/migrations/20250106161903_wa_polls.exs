defmodule Glific.Repo.Migrations.WaPolls do
  use Ecto.Migration

  def change do
    create table(:wa_polls) do
      add :uuid, :uuid,
        null: false,
        comment: "Uniquely generated message UUID, primarily needed for using in a flow webhook"

      add :label, :string, null: false, comment: "Title of the whatsapp poll"

      add :poll_content, :map,
        default: %{},
        comment: "poll content"

      add :allow_multiple_answer, :boolean,
        default: false,
        comment: "if users can select multiple answers in a WhatsApp poll or not"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    alter table(:wa_messages) do
      add :poll_id, references(:wa_polls, on_delete: :nilify_all),
        comment: "Reference for the Whatsapp groups poll"
    end

    alter table(:webhook_logs) do
      add :wa_group_id, references(:wa_groups, on_delete: :nilify_all)
      modify :contact_id, null: false
      modify :title, null: false, from: {:string, null: true}
    end

    create unique_index(:wa_polls, [:label, :organization_id])
    create unique_index(:wa_polls, [:uuid])
    create index(:wa_messages, [:poll_id], where: "poll_id IS NOT NULL")
  end
end
