defmodule Glific.Repo.Migrations.AddMessageNumberColumInTicketTable do
  use Ecto.Migration

  def change do
    alter table(:tickets) do
      add :message_number, :integer
    end
  end
end
