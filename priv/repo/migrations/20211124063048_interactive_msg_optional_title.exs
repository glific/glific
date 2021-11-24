defmodule Glific.Repo.Migrations.InteractiveMsgOptionalTitle do
  use Ecto.Migration

  def change do
    add_send_interactive_title()
  end

  defp add_send_interactive_title() do
    alter table(:interactive_templates) do
      add :send_interactive_title, :boolean,
        null: false,
        default: true,
        comment: "Field to check if title needs to be send in the interactive message"
    end
  end
end
