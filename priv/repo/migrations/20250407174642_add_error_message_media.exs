defmodule Glific.Repo.Migrations.AddErrorMessageMedia do
  use Ecto.Migration

  def change do
    alter table(:messages_media) do
      add :error, :text
    end
  end
end
