defmodule Glific.Repo.Migrations.AddWhatsappKeyIdToWaMessages do
  use Ecto.Migration

  def change do
    alter table(:wa_messages) do
      add :whatsapp_key_id, :string,
        comment:
          "Id part of the WhatsApp message key (e.g. 3EB0...), shared by every form of the WhatsApp message id. Used to match Maytapi reaction and poll vote events, which reference the WhatsApp id rather than the API uuid stored in bsp_id"
    end
  end
end
