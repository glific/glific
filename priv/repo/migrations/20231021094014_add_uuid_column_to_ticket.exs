defmodule Glific.Repo.Migrations.AddUuidColumnToTicket do
  use Ecto.Migration

  def change do
    alter table(:tickets) do
      add :uuid, :uuid, default: fragment("gen_random_uuid()")
    end
  end
end
