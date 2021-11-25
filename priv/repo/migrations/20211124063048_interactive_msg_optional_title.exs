defmodule Glific.Repo.Migrations.InteractiveMsgOptionalTitle do
  use Ecto.Migration

  def change do
    add_send_with_title()
  end

  defp add_send_with_title() do
    alter table(:interactive_templates) do
      add :send_with_title, :boolean,
        null: false,
        default: true,
        comment: "Field to check if title needs to be send in the interactive message"
    end
  end
end
