defmodule Glific.Repo.Migrations.AddWhatsappStateToContactIdentities do
  @moduledoc """
  Per-channel consent and session state belongs to the identity a contact uses on that channel, not to the
  contact. These are the columns of `contacts` that describe WhatsApp (opt-in, opt-out, the BSP session
  status and the 24 hour session clock), now also held on the contact's `(whatsapp, phone)` identity.

  The old `contacts` columns stay in place and are no longer written; they are read only for a contact whose
  WhatsApp identity row does not exist yet, until `Glific.Contacts.IdentityBackfill` has created every row.
  """
  use Ecto.Migration

  def change do
    alter table(:contact_identities) do
      add :optin_time, :utc_datetime, comment: "When the contact opted in on this channel"

      add :optin_status, :boolean,
        default: false,
        null: false,
        comment: "Whether the contact is currently opted in on this channel"

      add :optin_method, :string, comment: "How the contact opted in, e.g. BSP, Import, WA"
      add :optout_time, :utc_datetime, comment: "When the contact opted out on this channel"
      add :optout_method, :string, comment: "How the contact opted out"

      add :bsp_status, :contact_provider_status_enum,
        default: "none",
        null: false,
        comment: "WhatsApp session and template reachability of the contact"

      add :last_message_at, :utc_datetime,
        comment:
          "When the contact last sent a message on this channel; starts the 24 hour session"
    end
  end
end
