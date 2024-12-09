defmodule Glific.Repo.Migrations.AddPollContentInWaMessages do
  use Ecto.Migration

  def change do
    alter table(:wa_messages) do
      add :poll_content, :jsonb, default: fragment("'[]'")
    end
  end
end
