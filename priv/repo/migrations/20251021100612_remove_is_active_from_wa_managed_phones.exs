defmodule Glific.Repo.Migrations.RemoveIsActiveFromWaManagedPhones do
  use Ecto.Migration

  def change do
    alter table(:wa_managed_phones) do
      remove :is_active
    end
  end
end
