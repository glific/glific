defmodule Glific.Repo.Migrations.AddWAManagedPhones do
  use Ecto.Migration

  def change do
    contacts()

    wa_managed_phones()

    wa_groups()

    wa_messages()
  end

  defp wa_managed_phones do
    create table(:wa_managed_phones) do
      add :label, :string, comment: "Identification for this phone"

      # phone number that we are using for external api
      add :phone, :string, null: false

      # other ids that that provider uses in the url (maytapi)
      add :phone_id, :integer
      add :product_id, :string

      add :is_active, :boolean,
        default: true,
        comment: "Whether the phone number is currently active"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:wa_managed_phones, :organization_id)
    create unique_index(:wa_managed_phones, :phone)
  end

  defp wa_messages do
    create table(:wa_messages) do
      add :label, :string, comment: "Identification for this phone"

      add :uuid, :uuid,
        null: true,
        comment: "Uniquely generated message UUID, primarily needed for the flow editor"

      add :body, :text, null: false, comment: "Body of the message"

      add :type, :message_type_enum,
        comment:
          "Type of the message; options are - text, audio, video, image, location, contact, file, sticker"

      add :flow, :message_flow_enum, comment: "Whether an inbound or an outbound message"

      add :status, :message_status_enum,
        null: false,
        default: "enqueued",
        comment: "Delivery status of the message"

      add :bsp_status, :contact_provider_status_enum,
        null: false,
        comment:
          "Whatsapp connection status; current options are : processing, valid, invalid & failed"

      add :errors, :map, comment: "Options : Sent, Delivered or Read"
      add :message_number, :bigint, comment: "Messaging number for a WhatsApp group"

      add :sender_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "Contact number of the sender of the message"

      add :receiver_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "Contact number of the receiver of the message"

      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment:
          "Either sender contact number or receiver contact number; created to quickly let us know who the beneficiary is"

      add :wa_managed_phone_id, references(:wa_managed_phones, on_delete: :delete_all),
        null: false,
        comment:
          "Either sender contact number or receiver contact number; created to quickly let us know who the beneficiary is"

      add :media_id, references(:messages_media, on_delete: :delete_all),
        null: true,
        comment: "Message media ID"

      add :send_at, :utc_datetime,
        null: true,
        comment: "Timestamp when message is scheduled to be sent"

      add :sent_at, :utc_datetime, comment: "Timestamp when message was sent from queue worker"

      add :wa_group_id, references(:wa_groups, on_delete: :delete_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID"

      timestamps(type: :utc_datetime_usec)
      add :context_id, :text, null: false, comment: "Body of the message"
      add :context_message_id, references(:wa_messages, on_delete: :delete_all), null: false

      add :message_broadcast_id, references(:message_broadcasts, on_delete: :delete_all),
        null: false
    end
  end

  defp contacts do
    alter table(:contacts) do
      add :contact_type, :string, comment: "one of WABA, WA, WABA+WA"
    end
  end

  defp wa_groups do
    create table(:wa_groups) do
      add :label, :string, null: false, comment: "Label of the WhatsApp group"

      add :wa_managed_phone_id, references(:wa_managed_phones, on_delete: :delete_all),
        null: false,
        comment: "WA managed phone the WhatsApp group is linked to"

      add :bsp_id, :string, comment: "Unique id of WhatsApp group provided by BSP"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID"

      timestamps(type: :utc_datetime)
    end

    create index(:wa_groups, [:wa_managed_phone_id, :organization_id])
    create unique_index(:wa_groups, [:bsp_id, :wa_managed_phone_id, :organization_id])
  end
end
