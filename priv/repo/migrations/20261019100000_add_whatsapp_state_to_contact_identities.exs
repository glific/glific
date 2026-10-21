defmodule Glific.Repo.Migrations.AddWhatsappStateToContactIdentities do
  @moduledoc """
  Per-channel consent and session state belongs to the identity a contact uses on that channel, not to the
  contact. These are the columns of `contacts` that describe WhatsApp (opt-in, opt-out, the BSP session
  status and the 24 hour session clock), now also held on the contact's `(whatsapp, phone)` identity.

  The old `contacts` columns stay in place for rollback, but are neither read nor written any more: a contact
  whose WhatsApp identity row does not exist yet reads as not opted in, until `Glific.Contacts.IdentityBackfill`
  has created every row from them.

  WhatsApp identity rows created before this migration (contacts created or re-phoned since identities
  shipped) get their contact's current state copied onto them here, since the backfill skips existing rows.
  They are few, so one statement is enough.
  """
  use Ecto.Migration

  @doc false
  def copy_state_sql do
    """
    UPDATE contact_identities i SET
      optin_time = c.optin_time,
      optin_status = COALESCE(c.optin_status, false),
      optin_method = c.optin_method,
      optout_time = c.optout_time,
      optout_method = c.optout_method,
      bsp_status = c.bsp_status,
      last_message_at = c.last_message_at
    FROM contacts c
    WHERE i.contact_id = c.id AND i.channel = 'whatsapp' AND i.identifier = c.phone
    """
  end

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

    execute(copy_state_sql(), "")
  end
end
