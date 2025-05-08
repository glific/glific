defmodule Glific.Repo.Migrations.AddErrorMessageMedia do
  use Ecto.Migration

  def change do
    alter table(:messages_media) do
      add :gcs_error, :text, comment: "Failure reason while trying to sync to gcs"
    end
  end
end
