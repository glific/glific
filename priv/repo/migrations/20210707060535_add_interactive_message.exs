defmodule Glific.Repo.Migrations.AddInteractiveMessage do
  use Ecto.Migration
  alias Glific.Enums.InteractiveMessageType

  def up do
    InteractiveMessageType.create_type()
    interactive()
  end

  def down do
    InteractiveMessageType.drop_type()
  end

  defp interactive do
    create table(:interactive_templates, comment: "Lets add interactive messages here") do
      add :label, :string, comment: "The label of the interactive message"

      add :type, :interactive_message_type_enum,
        comment: "The type of interactive message- quick_reply or list"

      add :interactive_content, :jsonb,
        default: "[]",
        comment: "Interactive content of the message stored in form of json"

      add :organization_id, references(:organizations, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:interactive_templates, [:label, :type, :organization_id])
    create index(:interactive_templates, :organization_id)
  end
end
