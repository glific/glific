defmodule Glific.Repo.Migrations.AlterMessagesWithIntractiveContent do
  use Ecto.Migration

  def change do
    alter_messages_with_intarctive_content()
  end

  def alter_messages_with_intarctive_content do
    alter table(:messages) do
      add_if_not_exists(:intarctive_content, :jsonb,
        comment: "the json data for list and payload"
      )
    end
  end

end
