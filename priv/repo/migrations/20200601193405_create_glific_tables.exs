defmodule Glific.Repo.Migrations.GlificCore do
  @moduledoc """
  To simplify things, lets create the bulk of the tables in one migration file for v0.1.
  This gives new developers a good view of the schema in one place.
  """

  use Ecto.Migration

  def change do
    providers()

    languages()

    organizations()

    tags()

    contacts()

    contacts_fields()

    flow_label()

    messages_media()

    session_templates()

    users()

    messages()

    messages_tags()

    contacts_tags()

    templates_tags()

    groups()

    contacts_groups()

    users_groups()

    saved_searches()

    locations()

    flows()

    flow_revisions()

    flow_contexts()

    flow_counts()
  end

  @doc """
  Since Language is such an important part of the communication, lets give language its
  own table. This allows us to optimize and switch languages relatively quickly
  """
  def languages do
    create table(:languages) do
      # The language label, typically the full name, like English (US) or Hindi
      add :label, :string, null: false

      # The language label in its default locale, e.g: हिंदी
      add :label_locale, :string, null: false

      # An optional description
      add :description, :string, null: true

      # The locale name of the language dialect, e.g. en_US, or hi
      add :locale, :string, null: false

      # Is this language being currently used in the sysem
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:languages, [:label, :locale])
  end

  @doc """
  All the organizations which are using this platform.
  """
  def organizations do
    create table(:organizations) do
      add :name, :string, null: false
      add :shortcode, :string, null: false

      add :email, :string, null: false

      add :provider_id, references(:providers, on_delete: :nothing), null: false
      add :provider_appname, :string, null: false

      # WhatsApp Business API Phone (this is the primary point of identification)
      # We will not link this to a contact
      add :provider_phone, :string, null: false

      # add a provider limit field to limit rate of messages / minute
      add :provider_limit, :integer, default: 60

      # choose active languages from the supported languages
      # organization default language
      add :default_language_id, references(:languages, on_delete: :restrict), null: false

      # choose active languages from the supported languages
      add :active_language_ids, {:array, :integer}, default: []

      # contact id of organization that can send messages out. We cannot make this a foreign
      # key due to cyclic nature. Hence definied as just an id
      # it will be null on creation and added when we add an organization
      add :contact_id, :integer

      # jsonb object of out_of_office data which is a bit convoluted to represent as columns
      add :out_of_office, :jsonb

      # organization services can be changed to inactive
      add :is_active, :boolean, default: true

      add :timezone, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, :shortcode)
    create unique_index(:organizations, :provider_phone)
    create unique_index(:organizations, :email)
    create unique_index(:organizations, :contact_id)
  end

  @doc """
  Multiple entities within the system like to be tagged. For e.g. Messages and Message Templates
  can be either manually tagged or automatically tagged.
  """
  def tags do
    create table(:tags) do
      # The tag label
      add :label, :string, null: false

      add :shortcode, :string, null: false

      # An optional description
      add :description, :string, null: true

      # Is this value being currently used
      add :is_active, :boolean, default: true

      # Is this a predefined system object?
      add :is_reserved, :boolean, default: false

      add :ancestors, {:array, :bigint}

      # Does this tag potentially have a value associated with it
      # If so, this value will be stored in the join tables. This is applicable only
      # for Numeric and Keyword message tags for now, but also include contact tags to
      # keep them in sync
      add :is_value, :boolean, default: false

      # keywords assosiacted with tags.
      add :keywords, {:array, :string}

      # define a color code for tags
      add :color_code, :string, default: "#0C976D"

      # foreign key to language
      add :language_id, references(:languages, on_delete: :restrict), null: false

      # All child tags point to the parent tag, this allows us a to organize tags as needed
      add :parent_id, references(:tags, on_delete: :nilify_all), null: true

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:shortcode, :language_id, :organization_id])
    create index(:tags, :organization_id)
  end

  @doc """
  Store a set of predefined messages that the organization communicates to its users
  on a regular basis.


  Handle multiple versions of the message for different languages. We will also need to think
  about incorporating short codes for session templates for easier retrieval by end user
  """
  def session_templates do
    create table(:session_templates) do
      # The template uuid, primarly needed for flow editor
      add :uuid, :uuid, null: false

      # The message label
      add :label, :string, null: false

      # The body of the message
      add :body, :text, null: false

      # Options are: text, audio, video, image, contact, location, file
      add :type, :message_type_enum

      # Is this a predefined system object?
      add :is_reserved, :boolean, default: false

      # Is this value being currently used
      add :is_active, :boolean, default: true

      # Is this the original root message
      add :is_source, :boolean, default: false

      # The message shortcode
      add :shortcode, :string, null: true

      # Field to check hsm message type
      add :is_hsm, :boolean, default: false

      # Number of parameters in hsm message
      add :number_parameters, :integer, null: true

      # Messages are in a specific language
      add :language_id, references(:languages, on_delete: :restrict), null: false

      # All child messages point to the root message, so we can propagate changes downstream
      add :parent_id, references(:session_templates, on_delete: :nilify_all), null: true

      # message media ids
      add :message_media_id, references(:messages_media, on_delete: :delete_all), null: true

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:session_templates, [:label, :language_id, :organization_id])
    create unique_index(:session_templates, [:shortcode, :language_id, :organization_id])
    create index(:session_templates, :organization_id)
    create unique_index(:session_templates, :uuid)
  end

  @doc """
  Minimal set of information to store for a Contact to record its interaction
  at a high level. Typically messaging apps dont have detailed information, and if
  they do, we'll redirect those requests to a future version of the CRMPlatform
  """
  def contacts do
    create table(:contacts) do
      # Contact Name
      add :name, :string

      # Contact Phone (this is the primary point of identification)
      # We will treat this as a whats app ID as well
      add :phone, :string, null: false

      # whatsapp status
      # the current options are: processing, valid, invalid, failed
      add :provider_status, :contact_provider_status_enum, null: false, default: "none"

      # this is our status, based on what the Provider tell us
      # the current options are: valid, invalid or blocked
      add :status, :contact_status_enum, null: false, default: "valid"

      # contact language for templates and other communications
      add :language_id, references(:languages, on_delete: :restrict), null: false

      # the times when we recorded either an optin or an optout
      # at some point, we will need to create an events table for this and track all changes
      add :optin_time, :utc_datetime
      add :optout_time, :utc_datetime

      # this is primarily used as a a cache to avoid querying the message table. We need this
      # to ensure we can send a valid session message to the user (< 24 hour window)
      add :last_message_at, :utc_datetime

      # store the settings of the user as a map (which is a jsonb object in psql)
      # preferences is one field in the settings (for now). The NGO can use this field to target
      # the user with messages based on their preferences. The user can select one or
      # more options from the preferenes list. All settings are checkboxes or multi-select.
      # at some point, merge this with fields, when we have type information
      add :settings, :map, default: %{}

      # store the NGO generated fields for the user also as a map
      # Each user can have multiple fields, we store the name as key
      add :fields, :map, default: %{}

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:contacts, [:name, :organization_id])
    create unique_index(:contacts, [:phone, :organization_id])
    create index(:contacts, :organization_id)
  end

  @doc """
  Information for all media messages sent and/or received by the system
  """
  def messages_media do
    create table(:messages_media) do
      # url to be sent to BSP
      add :url, :text, null: false

      # source url
      add :source_url, :text, null: false

      # thumbnail url
      add :thumbnail, :text

      # media caption
      add :caption, :text

      # whats app message id
      add :provider_media_id, :string

      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  Message structure for all messages send and/or received by the system
  """
  def messages do
    create table(:messages) do
      # Message uuid, primarly needed for flow editor
      add :uuid, :uuid, null: true

      # The body of the message
      add :body, :text

      # Options are: text, audio, video, image, contact, location, file
      add :type, :message_type_enum

      # Field to check hsm message type
      add :is_hsm, :boolean, default: false

      # Options are: inbound, outbound
      add :flow, :message_flow_enum

      # this is our status, It will tell us that
      # message got created but could not send because contact has optout
      add :status, :message_status_enum, null: false, default: "enqueued"

      # whats app message id
      add :provider_message_id, :string, null: true

      # options: sent, delivered, read
      add :provider_status, :message_status_enum

      # options: sent, delivered, read
      add :errors, :map

      # message number for a contact
      add :message_number, :bigint

      # sender id
      add :sender_id, references(:contacts, on_delete: :delete_all), null: false

      # receiver id
      add :receiver_id, references(:contacts, on_delete: :delete_all), null: false

      # contact id - this is either sender_id or receiver_id, but lets us know quickly
      # in queries who the beneficiary is. We otherwise need to check the :flow field to
      # use either the sender or receiver
      # this is a preliminary optimization to make the code cleaner
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false

      # user id - this will be null for automated messages and messages received
      add :user_id, references(:users, on_delete: :nilify_all), null: true

      # message media ids
      add :media_id, references(:messages_media, on_delete: :delete_all), null: true

      # timestamp when message is scheduled to be sent
      add :send_at, :utc_datetime, null: true

      # timestamp when message was sent from queue worker
      add :sent_at, :utc_datetime

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:sender_id])
    create index(:messages, [:receiver_id])
    create index(:messages, [:contact_id])
    create index(:messages, [:user_id])
    create index(:messages, :organization_id)
  end

  @doc """
  The join table between contacts and tags
  """
  def contacts_tags do
    create table(:contacts_tags) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false

      # the value of the tag if applicable
      add :value, :string
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

      # the value of the tag if applicable
      add :value, :string
    end

    create unique_index(:messages_tags, [:message_id, :tag_id])
  end

  @doc """
  Information of all the Business Service Providers (APIs) responsible for the communications.
  """
  def providers do
    create table(:providers) do
      # The name of Provider
      add :name, :string, null: false

      # The url of Provider
      add :url, :string, null: false

      # The api end point for Provider
      add :api_end_point, :string, null: false

      # add the handler and worker fields
      add :handler, :string, null: false
      add :worker, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:providers, :name)
  end

  @doc """
  All the system and user defined searches
  """
  def saved_searches() do
    create table(:saved_searches) do
      add :label, :string, null: false

      # the search arguments, stored as is in a jsonb blob
      add :args, :map

      # The shortcode to display in UI
      add :shortcode, :string, null: true

      # Is this a predefined system object?
      add :is_reserved, :boolean, default: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:saved_searches, [:shortcode, :organization_id])
    create index(:saved_searches, :organization_id)
  end

  @doc """
  Groups for users and contacts
  """
  def groups do
    create table(:groups) do
      # Label of the group
      add :label, :string, null: false

      # Description of the group
      add :description, :string, null: true

      # visibility of conversations to the other groups
      add :is_restricted, :boolean, default: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:groups, [:label, :organization_id])
    create index(:groups, :organization_id)
  end

  @doc """
  The join table between contacts and groups
  """
  def contacts_groups do
    create table(:contacts_groups) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :group_id, references(:groups, on_delete: :delete_all), null: false
    end

    create unique_index(:contacts_groups, [:contact_id, :group_id])
  end

  def users do
    create table(:users) do
      add :phone, :string, null: false
      add :password_hash, :string

      add :name, :string
      add :roles, {:array, :user_roles_enum}, default: ["none"]

      add :contact_id, references(:contacts, on_delete: :nilify_all), null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:phone, :organization_id])
    create unique_index(:users, :contact_id)
    create index(:users, :organization_id)
  end

  @doc """
  The join table between users and groups
  """
  def users_groups do
    create table(:users_groups) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :group_id, references(:groups, on_delete: :delete_all), null: false
    end

    create unique_index(:users_groups, [:user_id, :group_id])
  end

  @doc """
  Contact's current location storage.
  """
  def locations do
    create table(:locations) do
      # contact id of the sender
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false

      # reference to the incoming message
      add :message_id, references(:messages, on_delete: :delete_all), null: false

      # location longitude
      add :longitude, :float, null: false

      # location latitude
      add :latitude, :float, null: false

      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  Organization flow storage
  """
  def flows do
    create table(:flows) do
      add :name, :string, null: false
      add :uuid, :uuid, null: false

      add :version_number, :string, default: "13.1.0"
      add :flow_type, :flow_type_enum, null: false, default: "message"

      # Enable ignore keywords while in the flow
      add :ignore_keywords, :boolean, default: false

      # List of keywords to trigger the flow
      add :keywords, {:array, :string}, default: []

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flows, [:name, :organization_id])
    create unique_index(:flows, :uuid)
    create index(:flows, :organization_id)
  end

  @doc """
  Revisions for a flow
  """
  def flow_revisions do
    create table(:flow_revisions) do
      add :definition, :map
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :revision_number, :integer, default: 0

      # Status of flow revision draft or done
      add :status, :string, default: "draft"

      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  The Context that a contact is in with respect to a flow
  """
  def flow_contexts do
    create table(:flow_contexts) do
      add :node_uuid, :uuid, null: true
      add :flow_uuid, :uuid, null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      add :results, :map, default: %{}

      add :parent_id, references(:flow_contexts, on_delete: :nilify_all), null: true

      add :wakeup_at, :utc_datetime, null: true, default: nil
      add :completed_at, :utc_datetime, null: true, default: nil

      # Add list of recent messages for both inbound and outbound
      # for outbound we store the uuid
      add :recent_inbound, :jsonb, default: "[]"
      add :recent_outbound, :jsonb, default: "[]"

      timestamps(type: :utc_datetime)
    end

    create index(:flow_contexts, :flow_uuid)
    create index(:flow_contexts, [:flow_id, :contact_id])
  end

  @doc """
  Keep track of the number of times we pass through either a node or an exit
  to display to the staff via the floweditor interface.
  """
  def flow_counts do
    create table(:flow_counts) do
      add :uuid, :uuid, null: false

      add :destination_uuid, :uuid, null: true

      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      add :flow_uuid, :uuid, null: false

      # Options are: node, exit
      add :type, :string

      add :count, :integer, default: 1

      add :recent_messages, {:array, :map}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_counts, [:uuid, :flow_id, :type])
  end

  @doc """
  The join table between session templates and tags
  """
  def templates_tags do
    create table(:templates_tags) do
      add :template_id, references(:session_templates, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false

      # the value of the tag if applicable
      add :value, :string
    end

    create unique_index(:templates_tags, [:template_id, :tag_id])
  end

  @doc """
  Create contact fields to support flow editor and allow the user access to NGO specific
  fields
  """
  def contacts_fields do
    create table(:contacts_fields) do
      add :name, :string

      add :shortcode, :string

      # lets make this an enum with the following values
      # :text, :integer, :number, :boolean, :date
      add :value_type, :contact_field_value_type_enum

      # scope of variable
      # for now - contact or globals, maybe an enum also
      add :scope, :contact_field_scope_enum

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contacts_fields, [:name, :organization_id])
    create unique_index(:contacts_fields, [:shortcode, :organization_id])
  end

  @doc """
  Create flow label to associate flow messages with label
  """
  def flow_label do
    create table(:flow_label) do
      add :uuid, :uuid, null: false
      add :name, :string

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    create unique_index(:flow_label, [:name, :organization_id])
  end
end
