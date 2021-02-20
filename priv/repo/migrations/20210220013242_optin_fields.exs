defmodule Glific.Repo.Migrations.OptinFields do
  use Ecto.Migration

  alias Glific.{Contacts.Contact, Repo}

  def change do
    optin()
  end

  defp optin() do
    alter table(:contacts) do
      add :optin_method, :string,
        null: true,
        comment: "possible options include: URL, WhatsApp Message, QR Code, SMS, NGO"

      add :optin_status, :boolean,
        default: false,
        comment: "record if the contact has either opted or skipped the option"

      add :optin_message_id, :string,
        null: true,
        comment: "For whatsapp option, we'll record the wa-message-id sent"
    end

    # we always query optin_status with the organization_id
    create index(:contacts, [:optin_status, :organization_id])
  end
end
