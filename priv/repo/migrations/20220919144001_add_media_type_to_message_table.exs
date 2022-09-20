defmodule Glific.Repo.Migrations.AddMediaTypeToMessageTable do
  use Ecto.Migration

  def change do
    alter table(messages_media) do
      add :media_type, :string
    end
  end
end
