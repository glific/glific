defmodule Glific.Repo.Migrations.AlterMessagesWithIntractiveContent do
  use Ecto.Migration

  def change do
    alter_messages_with_intarctive_content()
  end

  def alter_messages_with_intarctive_content do
    alter table(:messages) do
      add_if_not_exists(:intarctive_content, :map,
        default: %{},
        comment: "the json data for intrative messages"
      )
    end
  end

end
