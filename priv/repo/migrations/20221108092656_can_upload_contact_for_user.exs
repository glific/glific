defmodule Glific.Repo.Migrations.CanUploadContactForUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:upload_contacts, :boolean, default: false, comment: "If user can upload the contacts.")
    end
  end
end
