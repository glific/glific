defmodule Glific.Repo.Migrations.GlificTables do
  @moduledoc """
  To simplify things, lets create the bulk of the tables in one migration file for v0.1.
  This gives new developers a good view of the schema in one place.
  """

  use Ecto.Migration

  def change do
    languages()

    tags()

    contacts()

    messages_media()

    session_templates()

    users()

    messages()

    messages_tags()

    contacts_tags()

    providers()

    organizations()

    groups()

    contacts_groups()

    users_groups()

    saved_searches()

    questions()

    question_sets()

    questions_question_sets()

    questions_answers()

    locations()

    flows()

    flow_revisions()

    flow_contexts()
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

      # Does this tag potentially have a value associated with it
      # If so, this value will be stored in the join tables. This is applicable only
      # for Numeric and Keyword message tags for now, but also include contact tags to
      # keep them in sync
      add :is_value, :boolean, default: false

      # keywords assosiacted with tags.
      add :keywords, {:array, :string}

      # foreign key to  option_value:value column with the option_group.name being "language"
      add :language_id, references(:languages, on_delete: :restrict), null: false

      # All child tags point to the parent tag, this allows us a to organize tags as needed
      add :parent_id, references(:tags, on_delete: :nilify_all), null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:label, :language_id])
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

      timestamps(type: :utc_datetime)
    end

    create unique_index(:session_templates, [:label, :language_id])
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
      add :provider_status, :contact_status_enum, null: false, default: "valid"

      # Is this contact active (for some definition of active)
      add :is_active, :boolean, default: true

      # this is our status, based on what the Provider tell us
      # the current options are: valid or invalid
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
      # more options from the preferenes list
      add :settings, :map

      # store the NGO generated fields for the user also as a map
      # Each user can have multiple fields, we store the name as key
      add :fields, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contacts, :phone)
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

      # timestamp when message will be sent from queue worker
      add :sent_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:sender_id])
    create index(:messages, [:receiver_id])
    create index(:messages, [:contact_id])
    create index(:messages, [:media_id])
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

      timestamps(type: :utc_datetime)
    end

    create unique_index(:providers, :name)
  end

  @doc """
  All the organizations which are using this platform.
  """
  def organizations do
    create table(:organizations) do
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :contact_name, :string, null: false
      add :contact_id, references(:contacts, on_delete: :nothing)
      add :email, :string, null: false
      add :provider, :string
      add :provider_id, references(:providers, on_delete: :nothing), null: false
      add :provider_key, :string, null: false
      add :provider_number, :string, null: false

      # organization default language
      add :default_language_id, references(:languages, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, :name)
    create unique_index(:organizations, :provider_number)
    create unique_index(:organizations, :email)
    create unique_index(:organizations, :contact_id)
  end

  @doc """
    All the system and user defined searches
  """

  def saved_searches() do
    create table(:saved_searches) do
      add :label, :string, null: false
      add :args, :map
      # Is this a predefined system object?
      add :is_reserved, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:saved_searches, :label)
  end

  @doc """
  Groups for users and contacts
  """
  def groups do
    create table(:groups) do
      # Label of the group
      add :label, :string, null: false
      # visibility of conversations with to the other groups
      add :is_restricted, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:groups, :label)
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
      add :roles, {:array, :string}, default: ["none"]

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:phone])
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
  The question table. Since all questions are of the same type, we wont
  split it for now. At some point i assume we will
  """
  def questions do
    create table(:questions) do
      # question label
      add :label, :string, null: false

      # question text is linked to a session template
      # via a shortcode since it can be in multiple languages
      add :shortcode, :string, null: false

      # only 3 types allowed for now: text, numeric and date
      add :type, :question_type_enum, null: false

      # should we clean punctuation and eliminate multiple spaces
      # this will also downcase the string
      add :clean_answer, :boolean, default: true

      # should we remove all spaces and punctuations
      add :strip_answer, :boolean, default: false

      # should we validate the answer
      add :validate_answer, :boolean, default: false

      # since we are dealing with multiple languages, we need to allow multiple answers
      # in some cases, multiple answers might be totally fine
      add :valid_answers, {:array, :string}

      # number of times we re-ask the question if we dont understand the answer
      add :number_retries, :integer, default: 2

      # the shortcode of the message we need to send the user in case of an error
      add :shortcode_error, :string

      # we might also want to store this response in a different entity
      # this callback will do the needful, including transforming the answer
      # we call this for valid answers only
      add :callback, :string

      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  The Question Set Table. All questions belong to a question set. A question can belong to one
  or more question sets. This allows us to ask questions from a question set in specific contexts
  """
  def question_sets do
    create table(:question_sets) do
      # question set label
      # there will be at least one global question set
      # for questions like language, maybe optout?
      add :label, :string, null: false

      # number of questions that have to be answered correctly
      # for this to be considered a pass
      # a 0 basically indicates not to validate
      add :number_questions_right, :integer, default: 0

      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  The join table between questions and question sets
  """
  def questions_question_sets do
    create table(:questions_question_sets) do
      add :question_id, references(:questions, on_delete: :delete_all), null: false
      add :question_sets_id, references(:question_sets, on_delete: :delete_all), null: false
    end
  end

  @doc """
  The Answer Storage. We store all the answers in a table. We expect the NGO to
  download and process these answers as they come in. This acts as a temporary storage
  for a brief period of time (weeks?)
  """
  def questions_answers do
    create table(:questions_answers) do
      # who has answered this questions?
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false

      # reference to the incoming message
      add :message_id, references(:messages, on_delete: :delete_all), null: false

      add :question_id, references(:questions, on_delete: :delete_all), null: false
      add :question_sets_id, references(:question_sets, on_delete: :delete_all), null: false

      # for now all answers are stored as string
      # at some point, we might split it based on question type
      add :answer, :string, null: false

      timestamps(type: :utc_datetime)
    end
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
      add :shortcode, :string, null: false
      add :uuid, :uuid, null: false
      add :version_number, :string, default: "13.1.0"
      add :language_id, references(:languages, on_delete: :restrict), null: false
      add :flow_type, :flow_type_enum, null: false, default: "message"
      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  Revisions for a flow
  """
  def flow_revisions do
    create table(:flow_revisions) do
      add :definition, :map
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :revision_number, :integer, default: 0

      timestamps(type: :utc_datetime)
    end
  end

  @doc """
  The Context that a contact is in with respect to a flow
  """
  def flow_contexts do
    create table(:flow_contexts) do
      add :node_uuid, :uuid, null: true
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      add :parent_id, references(:flow_contexts, on_delete: :nilify_all), null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flow_contexts, [:contact_id, :parent_id])
  end
end
