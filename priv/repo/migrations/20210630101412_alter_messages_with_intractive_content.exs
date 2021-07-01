defmodule Glific.Repo.Migrations.AlterMessagesWithIntractiveContent do
  use Ecto.Migration

  def change do
    alter_messages_with_interactive_content()
  end

  def alter_messages_with_interactive_content do
    alter table(:messages) do
      add_if_not_exists(:interactive_content, :map,
        default: %{},
        comment: "the json data for intrative messages"
      )
    end
  end

end
