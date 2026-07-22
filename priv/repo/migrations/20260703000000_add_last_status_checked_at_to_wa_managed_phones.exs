defmodule Glific.Repo.Migrations.AddLastStatusCheckedAtToWaManagedPhones do
  use Ecto.Migration

  def change do
    alter table(:wa_managed_phones) do
      add :last_status_checked_at, :utc_datetime_usec,
        comment: "When the phone's status was last reconciled against Maytapi (webhook or poll)"
    end
  end
end
