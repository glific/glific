defmodule Glific.Repo.Migrations.ContactsFirstMessageNumber do
  use Ecto.Migration

  def change do
    alter table(:contacts) do
      add :first_message_number, :integer, default: 1
    end
  end
end
