defmodule Glific.Repo.Migrations.AddTwowayTables do
  @moduledoc """
  To simplify things, lets create the bulk of the tables in one migration file for v0.1.
  This gives new developers a good view of the schema in one place.
  """

  use Ecto.Migration

  def change do
    languages()

    tags()

    session_messages()

    contacts()

    message_media()

    messages()
  end

  @doc """
  Since Language is such an important part of the communication, lets give language its
  own table. This allows us to optimize and switch languages relatively quickly
  """
  def languages do
    create table(:languages) do
      # The language label, typically the full name, like English (US) or Hindi
      add :label, :string, null: false

      # An optional description
      add :description, :string, null: true

      # The locale name of the language dialect, e.g. en_US, or hi_IN
      add :locale, :string, null: false

      # Is this language being currently used in the sysem
      add :is_active, :boolean, default: true

      timestamps()
    end

    create unique_index(:languages, :label)
    create unique_index(:languages, :locale)
  end

  @doc """
  Multiple entities within the system like to be tagged. For e.g. Messages and Message Templates
  can be either manually tagged or automatically tagged.
  """
  def tags do
    create table(:tags) do
      # The tag label
      add :label, :string, null: false

      # An optional description
      add :description, :string, null: true

      # Is this value being currently used
      add :is_active, :boolean, default: true

      # Is this a predefined system object?
      add :is_reserved, :boolean, default: false

      # foreign key to  option_value:value column with the option_group.name being "language"
      add :language_id, references(:languages, on_delete: :restrict), null: false

      # All child tags point to the parent tag, this allows us a to organize tags as needed
      add :parent_id, references(:tags, on_delete: :nilify_all), null: true

      timestamps()
    end

    create unique_index(:tags, [:label, :language_id])
  end

  @doc """
  Store a set of predefined messages that the organization communicates to its users
  on a regular basis.

  Handle multiple versions of the message for different languages. We will also need to think
  about incorporating short codes for session messages for easier retrieval by end user
  """
  def session_messages do
    create table(:session_messages) do
      # The message label
      add :label, :string, null: false

      # The body of the message
      add :body, :text, null: false

      # Is this a predefined system object?
      add :is_reserved, :boolean, default: false

      # Is this value being currently used
      add :is_active, :boolean, default: true

      # Is this the original root message
      add :is_source, :boolean, default: false

      # Is this translation machine-generated
      add :is_translated, :boolean, default: false

      # Messages are in a specific language
      add :language_id, references(:languages, on_delete: :restrict), null: false

      # All child messages point to the root message, so we can propagate changes downstream
      add :parent_id, references(:session_messages, on_delete: :nilify_all), null: true

      timestamps()
    end

    create unique_index(:session_messages, [:label, :language_id])
  end

  @doc """
  Minimal set of information to store for a Contact to record its interaction
  at a high level. Typically messaging apps dont have detailed information, and if
  they do, we'll redirect those requests to a future version of the CRMPlatform
  """
  def contacts do
    create table(:contacts) do
      # Contact Name
      add :name, :string, null: false

      # Contact Phone (this is the primary point of identification)
      add :phone, :string, null: false

      # whatsapp status
      # the current options are: processing, valid, invalid, failed
      add :wa_status, :contact_status_enum, null: false, default: "valid"

      # whatsapp id
      # this is relevant only if wa_status is valid
      add :wa_id, :string

      # Is this contact active (for some definition of active)
      add :is_active, :boolean, default: true

      # this is our status, based on what the BSP tell us
      # the current options are: valid or invalid
      add :status, :contact_status_enum, null: false, default: "valid"
      add :optin_time, :timestamptz
      add :optout_time, :timestamptz

      timestamps()
    end

    create unique_index(:contacts, :phone)
    create unique_index(:contacts, :wa_id)
  end

  @doc """
  Information for all media messages sent and/or received by the system
  """
  def message_media do
    create table(:message_media) do
      # url to be sent to BSP
      add :url, :text

      # source url
      add :source_url, :text

      # thumbnail url
      add :thumbnail, :text

      # media caption
      add :caption, :text

      # whats app message id
      add :wa_media_id, :string

      timestamps()
    end
  end

  @doc """
  Message structure for all messages send and/or received by the system
  """
  def messages do
    create table(:messages) do
      # The body of the message
      add :body, :text

      # Options are: text, audio, video, image, contact, location, file
      add :type, :message_types_enum

      # Options are: inbound, outbound
      add :flow, :message_flow_enum

      # whats app message id
      add :wa_message_id, :string, null: true

      # options: sent, delivered, read
      add :wa_status, :message_status_enum

      # sender id
      add :sender_id, references(:contacts, on_delete: :delete_all), null: false

      # recipient id
      add :recipient_id, references(:contacts, on_delete: :delete_all), null: false

      # message media ids
      add :media_id, references(:message_media, on_delete: :delete_all), null: true

      timestamps()
    end

    create index(:messages, [:sender_id])
    create index(:messages, [:recipient_id])
    create index(:messages, [:media_id])
  end

  @doc """
  The join table between contacts and tags
  """
  def contacts_tags do
    create table(:contacts_tags) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:contacts_tags, [:contact_id, :tag_id])
  end

  @doc """
  The join table between messages and tags
  """
  def messages_tags do
    create table(:messages_tags) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:messages_tags, [:message_id, :tag_id])
  end
end
