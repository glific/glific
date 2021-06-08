defmodule Glific.Repo.Migrations.GlificCore do
  @moduledoc """
  To simplify things, lets create the bulk of the tables in one migration file for v0.1.
  This gives new developers a good view of the schema in one place.
  """

  use Ecto.Migration

  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    execute("CREATE SCHEMA IF NOT EXISTS global")

    providers()

    languages()

    organizations()

    tags()

    contacts()

    contacts_fields()

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
    create table(:languages,
             prefix: @global_schema,
             comment:
               "Languages table to optimize and switch between languages relatively quickly"
           ) do
      # The language label, typically the full name, like English (US) or Hindi
      add :label, :string,
        null: false,
        comment: "Language label, typically the full name - like English (US) or Hindi"

      # The language label in its default locale, e.g: हिंदी
      add :label_locale, :string,
        null: false,
        comment: "The language label in its default locale, e.g: हिंदी"

      # An optional description
      add :description, :string, null: true, comment: "Optional description for the language"

      # The locale name of the language dialect, e.g. en, or hi
      add :locale, :string,
        null: false,
        comment: "The locale name of the language dialect, e.g. en, or hi"

      # Is this language being currently used in the sysem
      add :is_active, :boolean,
        default: true,
        comment: "Whether language currently in use within the system or not"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:languages, [:label, :locale], prefix: @global_schema)
  end

  @doc """
  All the organizations which are using this platform.
  """
  def organizations do
    create table(:organizations, comment: "Organisations on the platform") do
      add :name, :string, null: false, comment: "Organisation name"
      add :shortcode, :string, null: false, comment: "Organisation shortcode"

      add :email, :string,
        null: false,
        comment: "Email provided by the organisation for registration"

      add :provider_id, references(:providers, on_delete: :nothing, prefix: @global_schema),
        null: false

      add :provider_appname, :string, null: false

      # WhatsApp Business API Phone (this is the primary point of identification)
      # We will not link this to a contact
      add :provider_phone, :string,
        null: false,
        comment:
          "Whatsapp Business API Phone - primary point of identification for the organisation"

      # add a provider limit field to limit rate of messages / minute
      add :provider_limit, :integer,
        default: 60,
        comment: "Provider limit to limit the rate of messages per minute"

      # choose active languages from the supported languages
      # organization default language
      add :default_language_id,
          references(:languages, on_delete: :restrict, prefix: @global_schema),
          null: false,
          comment: "Default language for the organisation"

      # choose active languages from the supported languages
      add :active_language_ids, {:array, :integer},
        default: [],
        comment: "List of active languages used by the organisation from the supported languages"

      # contact id of organization that can send messages out. We cannot make this a foreign
      # key due to cyclic nature. Hence definied as just an id
      # it will be null on creation and added when we add an organization
      add :contact_id, :integer,
        comment: "Contact ID of the organisation that can send messages out"

      # jsonb object of out_of_office data which is a bit convoluted to represent as columns
      add :out_of_office, :jsonb, comment: "JSON object of the out of office information"

      # organization services can be changed to inactive
      add :is_active, :boolean,
        default: true,
        comment: "Whether an organisation's service is active or not"

      add :timezone, :string, comment: "Organization's operational timezone"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, :shortcode)
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
      add :label, :string, null: false, comment: "Labels of the created tags"

      add :shortcode, :string, null: false, comment: "Shortcodes of the created tags, if any"

      # An optional description
      add :description, :string, null: true, comment: "Optional description for the tags"

      # Is this value being currently used
      add :is_active, :boolean, default: true, comment: "Whether tags are currently in use or not"

      # Is this a predefined system object?
      add :is_reserved, :boolean,
        default: false,
        comment: "Whether the particular tag is a predefined system object or not"

      add :ancestors, {:array, :bigint}

      tags_value_comment = """
      Does this tag potentially have a value associated with it
      If so, this value will be stored in the join tables. This is applicable only
      for Numeric and Keyword message tags for now, but also include contact tags to
      keep them in sync
      """

      add :is_value, :boolean, default: false, comment: tags_value_comment

      # keywords assosiacted with tags.
      add :keywords, {:array, :string}, comment: "Keywords associated with the tags"

      # define a color code for tags
      add :color_code, :string,
        default: "#0C976D",
        comment: "Define a color code to associate it with a tag"

      # foreign key to language
      add :language_id, references(:languages, on_delete: :restrict, prefix: @global_schema),
        null: false,
        comment: "Foreign key for the language"

      # All child tags point to the parent tag, this allows us a to organize tags as needed
      add :parent_id, references(:tags, on_delete: :nilify_all),
        null: true,
        comment:
          "All child tags point to the parent tag, this allows for organizing tags as needed"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment:
          "Foreign key to organization restricting scope of this table to an organization only"

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
      add :uuid, :uuid,
        null: false,
        comment: "The template UUID, primarily needed for flow editor"

      # The message label
      add :label, :string, null: false, comment: "Message label"

      # The body of the message
      add :body, :text, null: false, comment: "Body of the message"

      # Options are: text, audio, video, image, contact, location, file, sticker
      add :type, :message_type_enum,
        comment:
          "Type of the message; options are - text, audio, video, image, location, contact, file, sticker"

      # Is this a predefined system object?
      add :is_reserved, :boolean,
        default: false,
        comment: "Whether the particular template is a predefined system object or not"

      # Is this value being currently used
      add :is_active, :boolean, default: true, comment: "Whether this value is currently in use"

      # Is this the original root message
      add :is_source, :boolean, default: false, comment: "Is this the original root message"

      # The message shortcode
      add :shortcode, :string, null: true, comment: "Message shortcode"

      # Field to check hsm message type
      add :is_hsm, :boolean, default: false, comment: "Field to check hsm message type"

      # Number of parameters in hsm message
      add :number_parameters, :integer, null: true, comment: "Number of parameters in HSM message"

      # Messages are in a specific language
      add :language_id, references(:languages, on_delete: :restrict, prefix: @global_schema),
        null: false,
        comment: "Language of the message"

      # All child messages point to the root message, so we can propagate changes downstream
      add :parent_id, references(:session_templates, on_delete: :nilify_all),
        null: true,
        comment: "Parent Message ID; all child messages point to the root message"

      # message media ids
      add :message_media_id, references(:messages_media, on_delete: :delete_all),
        null: true,
        comment: "Message media IDs"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique Organisation ID"

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
    create table(:contacts,
             comment: "Table for storing high level contact information provided by the user"
           ) do
      # Contact Name
      add :name, :string, comment: "User Name"

      # Contact Phone (this is the primary point of identification)
      # We will treat this as a whats app ID as well
      add :phone, :string,
        null: false,
        comment: "Phone number of the user; primary point of identification"

      # whatsapp status
      # the current options are: processing, valid, invalid, failed
      add :provider_status, :contact_provider_status_enum,
        null: false,
        default: "none",
        comment:
          "Whatsapp connection status; current options are : processing, valid, invalid & failed"

      # this is our status, based on what the Provider tell us
      # the current options are: valid, invalid or blocked
      add :status, :contact_status_enum,
        null: false,
        default: "valid",
        comment: "Provider status; current options are :valid, invalid or blocked"

      # contact language for templates and other communications
      add :language_id, references(:languages, on_delete: :restrict, prefix: @global_schema),
        null: false,
        comment: "Contact language for templates and other communications"

      # the times when we recorded either an optin or an optout
      # at some point, we will need to create an events table for this and track all changes
      add :optin_time, :utc_datetime, comment: "Time when we recorded an opt-in from the user"
      add :optout_time, :utc_datetime, comment: "Time when we recorded an opt-out from the user"

      # this is primarily used as a a cache to avoid querying the message table. We need this
      # to ensure we can send a valid session message to the user (< 24 hour window)
      add :last_message_at, :utc_datetime,
        comment:
          "Timestamp of most recent message sent by the user to ensure we can send a valid message to the user (< 24hr)"

      settings_comment = """
      Store the settings of the user as a map (which is a jsonb object in psql).
      Preferences is one field in the settings (for now). The NGO can use this field to target
      the user with messages based on their preferences. The user can select one or
      more options from the preferences list. All settings are checkboxes or multi-select.
      Merge this with fields, when we have type information
      """

      add :settings, :map, default: %{}, comment: settings_comment

      # store the NGO generated fields for the user also as a map
      # Each user can have multiple fields, we store the name as key
      add :fields, :map,
        default: %{},
        comment: "Labels and values of the NGO generated fields for the user"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"

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
      add :url, :text, null: false, comment: "URL to be sent to BSP"

      # source url
      add :source_url, :text, null: false, comment: "Source URL"

      # thumbnail url
      add :thumbnail, :text, comment: "Thumbnail URL"

      # media caption
      add :caption, :text, comment: "Media caption"

      # whats app message id
      add :provider_media_id, :string, comment: "Whatsapp message ID"

      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  Message structure for all messages send and/or received by the system
  """
  def messages do
    create table(:messages, comment: "Record of all messages sent and/or received by the system") do
      # Message uuid, primarly needed for flow editor
      add :uuid, :uuid,
        null: true,
        comment: "Uniquely generated message UUID, primarily needed for the flow editor"

      # The body of the message
      add :body, :text, comment: "Body of the message"

      # Options are: text, audio, video, image, contact, location, file, sticker
      add :type, :message_type_enum,
        comment:
          "Type of the message; options are - text, audio, video, image, location, contact, file, sticker"

      # Field to check hsm message type
      add :is_hsm, :boolean, default: false, comment: "Field to check hsm message type"

      # Options are: inbound, outbound
      add :flow, :message_flow_enum, comment: "Whether an inbound or an outbound message"

      # this is our status, It will tell us that
      # message got created but could not send because contact has optout
      add :status, :message_status_enum,
        null: false,
        default: "enqueued",
        comment: "Delivery status of the message"

      # whats app message id
      add :provider_message_id, :string, null: true, comment: "Whatsapp message ID"

      # options: sent, delivered, read
      add :provider_status, :message_status_enum, comment: "Options : Sent, Delivered or Read"

      # options: sent, delivered, read
      add :errors, :map, comment: "Options : Sent, Delivered or Read"

      # message number for a contact
      add :message_number, :bigint, comment: "Messaging number for a contact"

      # sender id
      add :sender_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "Contact number of the sender of the message"

      # receiver id
      add :receiver_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "Contact number of the receiver of the message"

      # contact id - this is either sender_id or receiver_id, but lets us know quickly
      # in queries who the beneficiary is. We otherwise need to check the :flow field to
      # use either the sender or receiver
      # this is a preliminary optimization to make the code cleaner
      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment:
          "Either sender contact number or receiver contact number; created to quickly let us know who the beneficiary is"

      # user id - this will be null for automated messages and messages received
      add :user_id, references(:users, on_delete: :nilify_all),
        null: true,
        comment: "User ID; this will be null for automated messages and messages received"

      # message media ids
      add :media_id, references(:messages_media, on_delete: :delete_all),
        null: true,
        comment: "Message media ID"

      # timestamp when message is scheduled to be sent
      add :send_at, :utc_datetime,
        null: true,
        comment: "Timestamp when message is scheduled to be sent"

      # timestamp when message was sent from queue worker
      add :sent_at, :utc_datetime, comment: "Timestamp when message was sent from queue worker"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique Organisation ID"

      timestamps(type: :utc_datetime)
    end

    create index(:messages, :contact_id)
    create index(:messages, :user_id, where: "user_id IS NOT NULL")
    create index(:messages, :media_id, where: "media_id IS NOT NULL")
    create index(:messages, :organization_id)
  end

  @doc """
  The join table between contacts and tags
  """
  def contacts_tags do
    create table(:contacts_tags) do
      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "Contact ID"

      add :tag_id, references(:tags, on_delete: :delete_all), null: false, comment: "Tag ID"

      # the value of the tag if applicable
      add :value, :string, comment: "Value of the tags, if applicable"
    end

    create unique_index(:contacts_tags, [:contact_id, :tag_id])
  end

  @doc """
  The join table between messages and tags
  """
  def messages_tags do
    create table(:messages_tags) do
      add :message_id, references(:messages, on_delete: :delete_all),
        null: false,
        comment: "Message ID"

      add :tag_id, references(:tags, on_delete: :delete_all), null: false, comment: "Tags ID"

      # the value of the tag if applicable
      add :value, :string, comment: "Value of the tags, if applicable"
    end

    create unique_index(:messages_tags, [:message_id, :tag_id])
  end

  @doc """
  Information of all the Business Service Providers (APIs) responsible for the communications.
  """
  def providers do
    create table(:providers, prefix: @global_schema) do
      # The name of Provider
      add :name, :string, null: false, comment: "Name of the provider"

      # The url of Provider
      add :url, :string, null: false, comment: "URL of the provider"

      # The api end point for Provider
      add :api_end_point, :string, null: false, comment: "API endpoint of the provider"

      # add the handler and worker fields
      add :handler, :string, null: false, comment: "Name of the handler"
      add :worker, :string, null: false, comment: "Name of the worker"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:providers, :name, prefix: @global_schema)
  end

  @doc """
  All the system and user defined searches
  """
  def saved_searches() do
    create table(:saved_searches) do
      add :label, :string, null: false

      # the search arguments, stored as is in a jsonb blob
      add :args, :map, comment: "Search arguments used by the user, saved as a jsonb blob"

      # The shortcode to display in UI
      add :shortcode, :string,
        null: true,
        comment: "Shortcode of the saved searches to display in UI"

      # Is this a predefined system object?
      add :is_reserved, :boolean, default: false, comment: "Is this a predefined system object?"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"

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
      add :label, :string, null: false, comment: "Label of the created groups"

      # Description of the group
      add :description, :string, null: true, comment: "Description of the groups"

      # visibility of conversations to the other groups
      add :is_restricted, :boolean,
        default: false,
        comment: "Visibility status of conversations to the other groups"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"

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
      add :phone, :string, null: false, comment: "User's Contact number"
      add :password_hash, :string, comment: "Password Hash"

      add :name, :string, comment: "User Name"
      add :roles, {:array, :user_roles_enum}, default: ["none"], comment: "User Role"

      add :contact_id, references(:contacts, on_delete: :nilify_all),
        null: false,
        comment: "Contact ID of the User"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"

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
      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "Contact ID of the sender"

      # reference to the incoming message
      add :message_id, references(:messages, on_delete: :delete_all),
        null: false,
        comment: "Reference to the incoming message"

      # location longitude
      add :longitude, :float, null: false, comment: "Location longitude"

      # location latitude
      add :latitude, :float, null: false, comment: "Location latitude"

      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  Organization flow storage
  """
  def flows do
    create table(:flows) do
      add :name, :string, null: false, comment: "Name of the created flow"
      add :uuid, :uuid, null: false, comment: "Unique ID generated for each flow"

      add :version_number, :string, default: "13.1.0", comment: "Flow version"

      add :flow_type, :flow_type_enum,
        null: false,
        default: "message",
        comment: "Type of flow; default - message"

      # Enable ignore keywords while in the flow
      add :ignore_keywords, :boolean,
        default: false,
        comment: "Enabling ignore keywords while in the flow"

      # List of keywords to trigger the flow
      add :keywords, {:array, :string},
        default: [],
        comment: "List of keywords to trigger the flow"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"

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
      add :flow_id, references(:flows, on_delete: :delete_all), null: false, comment: "Flow ID"

      add :revision_number, :integer,
        default: 0,
        comment: "Record of the revision made on the flow"

      # Status of flow revision draft or done
      add :status, :string, default: "draft", comment: "Status of flow revision draft or done"

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
end
