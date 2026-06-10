defmodule Glific.Repo.Migrations.AddWaMsgIdToWaMessages do
  use Ecto.Migration

  def change do
    alter table(:wa_messages) do
      add :wa_msg_id, :string,
        comment: "WhatsApp message id, used to dedup multi-phone echoes of the same message."
    end

    create index(:wa_messages, [:wa_msg_id])
  end
end
