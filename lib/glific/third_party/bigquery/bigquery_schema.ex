defmodule Glific.BigQuery.Schema do
  @moduledoc """
  Schema for tables to be created for a dataset
  """

  @doc """
  Schema for contacts table
  """
  # codebeat:disable[LOC]
  @spec contact_schema :: list()
  def contact_schema do
    [
      %{
        description: "Unique ID for the contact",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "User name",
        name: "name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Phone number of the user; primary point of identification",
        name: "phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description:
          "Whatsapp connection status; current options are : processing, valid, invalid & failed",
        name: "provider_status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Provider status; current options are :valid, invalid or blocked",
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Opted language of the user for templates and other communications",
        name: "language",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "The source from the contact got optin into Glific",
        name: "contact_optin_method",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when we recorded an opt-in from the user",
        name: "optin_time",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when we recorded an opt-out from the user",
        name: "optout_time",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description:
          "Timestamp of most recent message sent by the user to ensure we can send a valid message to the user (< 24hr)",
        name: "last_message_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "If contact is a user and their respective user name",
        name: "user_name",
        type: "string",
        mode: "NULLABLE"
      },
      %{
        description: "If contact is a user and their respective role",
        name: "user_role",
        type: "string",
        mode: "NULLABLE"
      },
      %{
        description: "NGO generated fields for the user generated as a map",
        name: "fields",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            description: "Labels for NGO generated fields for the user",
            name: "label",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            description: "Values of the NGO generated fields (mapped for each user and label)",
            name: "value",
            type: "string",
            mode: "NULLABLE"
          },
          %{
            description: "Type of the generated fields; example - string",
            name: "type",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            description: "Time of entry of the recorded field",
            name: "inserted_at",
            type: "DATETIME",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        description: "Store the settings of the user as a map (which is a jsonb object in psql).
      Preferences is one field in the settings (for now). The NGO can use this field to target
      the user with messages based on their preferences",
        name: "settings",
        type: "RECORD",
        mode: "NULLABLE",
        fields: [
          %{
            description: "Labels for the settings generated for the user",
            name: "label",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            description: "Values of the generated user settings (mapped for each label)",
            name: "values",
            type: "RECORD",
            mode: "REPEATED",
            fields: [
              %{
                name: "key",
                type: "STRING",
                mode: "NULLABLE"
              },
              %{
                name: "value",
                type: "STRING",
                mode: "NULLABLE"
              }
            ]
          }
        ]
      },
      %{
        description: "Last login date of the staff member",
        name: "last_login_as_staff_at",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "IP address of the device last login from",
        name: "last_login_from_as_staff",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Flag indicating if the user is restricted",
        name: "is_restricted_user",
        type: "Boolean",
        mode: "NULLABLE"
      },
      %{
        description: "Groups that the contact belongs to",
        name: "groups",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            description: "Label of the group that the contact belongs to",
            name: "label",
            type: "STRING",
            mode: "REQUIRED"
          },
          %{
            description: "Description of the group that the contact belongs to",
            name: "description",
            type: "STRING",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        description: "Tags associated with the contact",
        name: "tags",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            description: "Labels for the associated tags",
            name: "label",
            type: "STRING",
            mode: "REQUIRED"
          }
        ]
      },
      %{
        description: "JSON object for storing the contact fields",
        name: "raw_fields",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Label of all the groups that the contact belongs to",
        name: "group_labels",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Type of contact, valid values are WA, WABA, WABA+WA",
        name: "contact_type",
        type: "STRING",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for messages table
  """
  @spec message_schema :: list()
  def message_schema do
    [
      %{
        description: "Unique ID generated for each message",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description:
          "Uniquely generated message UUID, in case of flow it's id of that particular node which have the message.",
        name: "uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Body of the message",
        name: "body",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description:
          "Type of the message; options are - text, audio, video, image, location, contact, file, sticker",
        name: "type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Whether an inbound or an outbound message",
        name: "flow",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Delivery status of the message",
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Message status as per the BSP. Options : Sent, Delivered or Read",
        name: "bsp_status",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Errors if any while sending the message",
        name: "errors",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Contact number of the sender of the message",
        name: "sender_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Contact number of the receiver of the message",
        name: "receiver_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description:
          "Either sender contact number or receiver contact number; created to quickly let us know who the beneficiary is",
        name: "contact_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description:
          "Either sender contact name or receiver contact name; created to quickly let us know who the beneficiary is",
        name: "contact_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "User ID; this will be null for automated messages and messages received",
        name: "user_phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "User contact name",
        name: "user_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Message media ID",
        name: "media_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Timestamp when message was sent from queue worker",
        name: "sent_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Tags assigned to the messages, if any",
        name: "tags_label",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Flow label associated with the message",
        name: "flow_label",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Flow associated with the message",
        name: "flow_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Flow UUID for joining with flow/flow_results",
        name: "flow_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Flow ID for joining with flow/flow_results",
        name: "flow_id",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Longitude from where the message was sent",
        name: "longitude",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Latitude from where the message was sent",
        name: "latitude",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "URL of media file stored in GCS",
        name: "gcs_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Status if the message was an HSM",
        name: "is_hsm",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "reference ID for an HSM",
        name: "template_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "reference ID for an interactive template",
        name: "interactive_template_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "context message id for an template response",
        name: "context_message_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "group message id when a flow started for a group",
        name: "group_message_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "flow broadcast id when a flow started for a group",
        name: "flow_broadcast_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "message broadcast id when a flow or message started for a group",
        name: "message_broadcast_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "ID of the message media table reference to the message media table",
        name: "media_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "ID of the profile table reference to the profile table",
        name: "profile_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "ID of group reference to the group table",
        name: "group_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "label of the group referenced to in group table",
        name: "group_name",
        type: "STRING",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for wa_group table
  """
  @spec wa_group_schema :: list()
  def wa_group_schema do
    [
      %{
        description: "Unique ID generated for each WA Group",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "label of WhatsApp group",
        name: "label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "WA managed phone",
        name: "wa_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when last message was sent/received from group",
        name: "last_communication_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "NGO generated fields for the wa group generated as a map",
        name: "fields",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            description: "Labels for NGO generated fields for the wa group",
            name: "label",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            description:
              "Values of the NGO generated fields (mapped for each wa group and label)",
            name: "value",
            type: "string",
            mode: "NULLABLE"
          },
          %{
            description: "Type of the generated fields; example - string",
            name: "type",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            description: "Time of entry of the recorded field",
            name: "inserted_at",
            type: "DATETIME",
            mode: "NULLABLE"
          }
        ]
      }
    ]
  end

  @doc """
  Schema for group table
  """
  @spec group_schema :: list()
  def group_schema do
    [
      %{
        description: "Unique ID generated for each WA Group",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "label of Group",
        name: "label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "description of Group",
        name: "description",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Flag indicating if the group is restricted",
        name: "is_restricted",
        type: "Boolean",
        mode: "REQUIRED"
      },
      %{
        description: "Type of Group either WABA or WA",
        name: "group_type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when last message was sent/received from group",
        name: "last_communication_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for flow label table
  """
  @spec flow_label_schema :: list()
  def flow_label_schema do
    [
      %{
        description: "Unique ID generated for each Flow Label",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "name of Flow Label",
        name: "name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "UUID of Flow Label",
        name: "uuid",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "type of Flow Label",
        name: "type",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for tag table
  """
  @spec tag_schema :: list()
  def tag_schema do
    [
      %{
        description: "Unique ID generated for each tag",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "label of tag",
        name: "label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "shortcode of tag",
        name: "shortcode",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "description of tag",
        name: "description",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Check for tag if it is active",
        name: "is_active",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Check for tag if it is reserved",
        name: "is_reserved",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for saved_search table
  """
  @spec saved_search_schema :: list()
  def saved_search_schema do
    [
      %{
        description: "Unique ID generated for each saved_search",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "label of saved_search",
        name: "label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "JSON object for storing the JSON of saved_search",
        name: "args",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "shortcode of saved_search",
        name: "shortcode",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Check for saved_search if it is reserved",
        name: "is_reserved",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for speed_send table
  """
  @spec speed_send_schema :: list()
  def speed_send_schema do
    [
      %{
        description: "Unique ID generated for each speed send",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "UUID of speed send",
        name: "UUID",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "label of speed send",
        name: "label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "body of speed send",
        name: "body",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "type of speed send",
        name: "type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Check for speed send if it is reserved",
        name: "is_reserved",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Check for speed send if it is active",
        name: "is_active",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Opted language of the speed send",
        name: "language",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "ID of media file in database",
        name: "media_id",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "URL of media file stored in GCS",
        name: "gcs_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Media URL if it is media speed spend",
        name: "media_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "JSON object for storing translations of speed send",
        name: "translations",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for wa_group_collections table
  """
  @spec wa_groups_collection_schema :: list()
  def wa_groups_collection_schema do
    [
      %{
        description: "Unique ID generated for each WA Group Collection",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "WA Group ID",
        name: "group_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Glific Collection ID",
        name: "collection_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "label of WhatsApp group",
        name: "group_label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "label of Glific collection",
        name: "collection_label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for contacts_wa_group table
  """
  @spec contacts_wa_group_schema :: list()
  def contacts_wa_group_schema do
    [
      %{
        description: "Unique ID generated for each contacts_wa_group",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Phone number of the contact",
        name: "phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "WA Group ID",
        name: "group_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "label of WhatsApp group",
        name: "group_label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Check for contact is Admin of Group",
        name: "is_admin",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for wa_reaction table
  """
  @spec wa_reactions_schema :: list()
  def wa_reactions_schema do
    [
      %{
        description: "Unique ID generated for each  wa_reactions",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Phone number of the contact",
        name: "phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "reaction message",
        name: "reaction",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "WA message ID",
        name: "wa_message_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Body of the message",
        name: "body",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for messages media table
  """
  @spec messages_media_schema :: list()
  def messages_media_schema do
    [
      %{
        description: "Unique ID generated for each message",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "caption we received with the message",
        name: "caption",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "URL of media file stored in provider",
        name: "url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "URL of media file stored in provider",
        name: "source_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Content Type of media file from provider",
        name: "content_type",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "URL of media file stored in GCS",
        name: "gcs_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for flows table
  """
  @spec flow_schema :: list()
  def flow_schema do
    [
      %{
        description: "Flow ID; key",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Name of the created flow",
        name: "name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Unique ID generated for each flow",
        name: "uuid",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the flow was first created",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the flow was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "List of keywords to trigger the flow",
        name: "keywords",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Status of flow revision draft or done",
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Revision number for the flow, if any revisions/modifications were made",
        name: "revision",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Tag added to the flow",
        name: "tag",
        type: "STRING",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for flow context table
  """
  @spec flow_context_schema :: list()
  def flow_context_schema do
    [
      %{
        description: "Flow Context ID; key",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Name of the Flow",
        name: "flow_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Name of the current node uuid flow",
        name: "node_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Unique ID generated for each flow",
        name: "flow_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Unique ID generated for each flow in the glific db",
        name: "flow_id",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "contact id references to the contact table",
        name: "contact_id",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "contact phone references to the contact table",
        name: "contact_phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "local result of a particular flow context",
        name: "results",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Few latest messages received by the contact",
        name: "recent_inbound",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Few latest messages sent to the contact",
        name: "recent_outbound",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Status of the flow context is it for draft or published only",
        name: "status",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Parent flow context id references to the flow context table",
        name: "parent_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description:
          "flow broadcast id references to the flow broadcast table, this is an old one. We will remove it in the future",
        name: "flow_broadcast_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "message broadcast id references to the flow broadcast table",
        name: "message_broadcast_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Check to see if the flow context is for a background or foreground flow",
        name: "is_background_flow",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description:
          "Check in case we killed the flow for a contact. Not when contact finished the flow",
        name: "is_killed",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Check for a flow results node",
        name: "is_await_result",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Check if the flow is waiting for a action or time to resume.",
        name: "wakeup_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the flow was killed or completed",
        name: "completed_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the flow was first created",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the flow was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "ID of the profile table reference to the profile table",
        name: "profile_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "ID of whatsapp group reference to the wa_group table",
        name: "wa_group_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "label of whatsapp group referenced to the wa_group table",
        name: "wa_group_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "bsp_id of whatsapp group reference to the wa_group table",
        name: "wa_group_bsp_id",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Reason behind the flow killed",
        name: "reason",
        type: "STRING",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for ticket table
  """
  @spec ticket_schema :: list()
  def ticket_schema do
    [
      %{
        description: "Ticket ID",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Body of the ticket",
        name: "body",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Topic of the ticket",
        name: "topic",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Status of the ticket",
        name: "status",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Remarks on the ticket",
        name: "remarks",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Contact ID on the ticket",
        name: "contact_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Contact name on the ticket",
        name: "contact_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Contact phone on the ticket",
        name: "contact_phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "User ID on the ticket",
        name: "user_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "User name on the ticket",
        name: "user_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "User phone on the ticket",
        name: "user_phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the ticket was first created",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the ticket was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Flow ID",
        name: "flow_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Name of the Flow",
        name: "flow_name",
        type: "STRING",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for flow results table
  """
  @spec flow_result_schema :: list()
  def flow_result_schema do
    [
      %{
        description: "Flow Result ID",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Name of the workflow",
        name: "name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description:
          "Unique ID of the flow; we store flows with both id and uuid, since flow editor always refers to a flow by its uuid ",
        name: "uuid",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the flow results entry was first created for a user",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the flow results entry was last updated for a user",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "JSON object for storing the user responses",
        name: "results",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Which specific published version of the flow is being referred to",
        name: "flow_version",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Phone number of the contact interacting with the flow",
        name: "contact_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Name of the contact interacting with the flow",
        name: "contact_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "ID of the flow context with which the user is associated to in the flow",
        name: "flow_context_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "ID of the profile table reference to the profile table",
        name: "profile_id",
        type: "INTEGER",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for flow count table
  """
  @spec flow_count_schema :: list()
  def flow_count_schema do
    [
      %{
        description: "Flow Count ID",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "UUID of the source node",
        name: "source_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "UUID of the destination node",
        name: "destination_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Name of the workflow",
        name: "flow_name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description:
          "Unique ID of the flow; we store flows with both id and uuid, since flow editor always refers to a flow by its uuid ",
        name: "flow_uuid",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Type of the node",
        name: "type",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Travel count for a node",
        name: "count",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the flow results entry was first created for a user",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the flow results entry was last updated for a user",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      }
    ]
  end

  @doc """
  Schema for the stats_global_schema table
  """
  @spec stats_all_schema :: list()
  def stats_all_schema do
    stats_schema() ++
      [
        %{
          description: "Organization ID",
          name: "organization_id",
          type: "INTEGER",
          mode: "REQUIRED"
        },
        %{
          description: "Organization Name",
          name: "organization_name",
          type: "STRING",
          mode: "NULLABLE"
        },
        %{
          description: "Organization Status",
          name: "organization_status",
          type: "STRING",
          mode: "NULLABLE"
        }
      ]
  end

  @doc """
  Schema for stats_schema table
  """
  @spec stats_schema :: list()
  def stats_schema do
    [
      %{
        description: "Stats ID",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Total number of contacts",
        name: "contacts",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Total number of active contacts",
        name: "active",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Number of opted in contacts",
        name: "optin",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Number of opted out contacts",
        name: "optout",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Total number of messages",
        name: "messages",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Total number of inbound messages",
        name: "inbound",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Total number of outbound messages",
        name: "outbound",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Total number of HSM messages (outbound only)",
        name: "hsm",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Total number of flows started today",
        name: "flows_started",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Total number of flows completed today",
        name: "flows_completed",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Total number of users active",
        name: "users",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "The period for this record: hour, day, week, month, summary",
        name: "period",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description:
          "All stats are measured with respect to UTC time, to keep things timezone agnostic.",
        name: "date",
        type: "DATE",
        mode: "NULLABLE"
      },
      %{
        description: "The hour that this record represents, 0..23, only for PERIOD: hour",
        name: "hour",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the stats entry was first created for a user",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the stats results entry was last updated for a user",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Total number of conversations",
        name: "conversations",
        type: "INTEGER",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for profile table
  """
  @spec profile_schema :: list()
  def profile_schema do
    [
      %{
        description: "Unique ID for the profile",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Profile Name",
        name: "name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Profile Type",
        name: "type",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the stats entry was first created for a user",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the stats results entry was last updated for a user",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "This is a field to sync contact with profile fields",
        name: "fields",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            description: "Labels for NGO generated fields for the user",
            name: "label",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            description: "Values of the NGO generated fields (mapped for each user and label)",
            name: "value",
            type: "string",
            mode: "NULLABLE"
          },
          %{
            description: "Type of the generated fields; example - string",
            name: "type",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            description: "Time of entry of the recorded field",
            name: "inserted_at",
            type: "DATETIME",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        description: "Phone number of the user; primary point of identification",
        name: "phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Opted language of the user for templates and other communications",
        name: "language",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Active status of the profile",
        name: "is_active",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Default status of the profile",
        name: "is_default",
        type: "BOOLEAN",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for contact history table
  """
  @spec contact_history_schema :: list()
  def contact_history_schema do
    [
      %{
        description: "Unique ID for the contact history",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "event type for the contact history",
        name: "event_type",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "event label for the contact history",
        name: "event_label",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "event datetime for the contact history",
        name: "event_datetime",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the stats entry was first created for a user",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the stats results entry was last updated for a user",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Phone number of the user; primary point of identification",
        name: "phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "ID of the profile table reference to the profile table",
        name: "profile_id",
        type: "INTEGER",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for message conversation table
  """
  @spec message_conversation_schema :: list()
  def message_conversation_schema do
    [
      %{
        description: "Unique ID for the message conversation",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Conversation ID for the message",
        name: "conversation_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Conversation ID for the message",
        name: "conversation_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Deduction type for the message conversation",
        name: "deduction_type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Status if the message conversation was billed",
        name: "is_billable",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the message conversation was first created",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the message conversation was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Reference for the message",
        name: "message_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Message conversation payload received from Gupshup",
        name: "payload",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Phone number of the contact",
        name: "phone",
        type: "STRING",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for message broadcast contacts table
  """
  @spec message_broadcast_contacts_schema :: list()
  def message_broadcast_contacts_schema do
    [
      %{
        description: "Unique ID for the message broadcast contacts",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Reference for the message broadcast",
        name: "message_broadcast_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Phone number of the contact",
        name: "phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Status of Broadcast",
        name: "status",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the message broadcast contact was processed",
        name: "processed_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the message broadcast contact was first created",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the message broadcast contact was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for message broadcasts table
  """
  @spec message_broadcasts_schema :: list()
  def message_broadcasts_schema do
    [
      %{
        description: "Unique ID for the message broadcast contacts",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Reference for the flow",
        name: "flow_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Name of the Flow",
        name: "flow_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Reference for the collection",
        name: "group_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Name of the collection",
        name: "group_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Status of Broadcast",
        name: "status",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Reference for the message",
        name: "message_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Reference for the user",
        name: "user_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Phone number of the user",
        name: "user_phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Type of broadcast",
        name: "broadcast_type",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Message Params",
        name: "message_params",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the message broadcast was started",
        name: "started_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the message broadcast was completed",
        name: "completed_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the message broadcast was first created",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the message broadcast was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for tracker table
  """
  @spec trackers_schema :: list()
  def trackers_schema do
    [
      %{
        description: "Unique ID for the trackers",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "PERIOD",
        name: "period",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "DATE",
        name: "date",
        type: "DATE",
        mode: "NULLABLE"
      },
      %{
        description: "JSON object for storing the user tracking",
        name: "counts",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the trackers data was first created",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the trackers data was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      }
    ]
  end

  @doc """
  Schema for wa_messages table
  """
  @spec wa_message_schema :: list()
  def wa_message_schema do
    [
      %{
        description: "Unique ID generated for each message",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description:
          "Uniquely generated message UUID, in case of flow it's id of that particular node which have the message.",
        name: "uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Body of the message",
        name: "body",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description:
          "Type of the message; options are - text, audio, video, image, location, contact, file, sticker",
        name: "type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Whether an inbound or an outbound message",
        name: "flow",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Delivery status of the message",
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "WA Message status as per the BSP. Options : Sent, Delivered or Read",
        name: "bsp_status",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Errors if any while sending the message",
        name: "errors",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description:
          "Either sender contact number or receiver contact number; created to quickly let us know who the beneficiary is",
        name: "contact_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description:
          "Either sender contact name or receiver contact name; created to quickly let us know who the beneficiary is",
        name: "contact_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Message media ID",
        name: "media_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Timestamp when wa message was sent from queue worker",
        name: "sent_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        description: "URL of media file stored in GCS",
        name: "gcs_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Status if the message was an HSM",
        name: "is_dm",
        type: "BOOLEAN",
        mode: "NULLABLE"
      },
      %{
        description: "message broadcast id when a flow or message started for a group",
        name: "message_broadcast_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "ID of the message media table reference to the message media table",
        name: "media_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "ID of group reference to the wa_group table",
        name: "wa_group_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "label of the group referenced to in wa_group table",
        name: "wa_group_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Flow label associated with the message",
        name: "flow_label",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Poll content",
        name: "poll_content",
        type: "STRING",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for the contact_groups table
  """
  @spec contact_groups_schema :: list()
  def contact_groups_schema do
    [
      %{
        description: "Unique ID for the contact groups",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Reference for the contact id",
        name: "contact_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Reference for the contact name",
        name: "name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Reference for the contact phone",
        name: "phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Reference for the collection",
        name: "group_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "Reference for the collection name",
        name: "group_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the contact was added in group",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the contact group was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for the contact_fields table
  """
  @spec contact_fields_schema :: list()
  def contact_fields_schema do
    [
      %{
        description: "Unique ID for the contact field",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Contact Field name",
        name: "name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Contact Field shortcode",
        name: "shortcode",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Scope of Contact Field",
        name: "scope",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the contact was added in group",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the contact group was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for the trackers_all_schema table
  """
  @spec trackers_all_schema :: list()
  def trackers_all_schema do
    trackers_schema() ++
      [
        %{
          description: "Organization ID",
          name: "organization_id",
          type: "INTEGER",
          mode: "REQUIRED"
        },
        %{
          description: "Organization Name",
          name: "organization_name",
          type: "STRING",
          mode: "NULLABLE"
        }
      ]
  end

  @doc """
  Schema for the registration table
  """
  @spec registration_schema :: list()
  def registration_schema do
    [
      %{
        description: "JSON object for storing details about the organization.",
        name: "org_details",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "JSON object for storing details about the Gupshup platform.",
        name: "platform_details",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "JSON object for storing billing details.",
        name: "finance_poc",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "JSON object for storing submitter details",
        name: "submitter",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "JSON object for storing signing authority details.",
        name: "signing_authority",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Frequency of billing one of yearly, monthly, quarterly",
        name: "billing_frequency",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "IP address of the submitter",
        name: "ip_address",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Flag indicating if the registration has been submitted.",
        name: "has_submitted",
        type: "Boolean",
        mode: "REQUIRED"
      },
      %{
        description: "Flag indicating if the user agreed or disagreed with the T&C",
        name: "terms_agreed",
        type: "Boolean",
        mode: "REQUIRED"
      },
      %{
        description: "Flag indicating if user agrees to create a support staff account",
        name: "support_staff_account",
        type: "Boolean",
        mode: "REQUIRED"
      },
      %{
        description: "if the user disputed the T&C",
        name: "is_disputed",
        type: "Boolean",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for the interactive templates table
  """
  @spec interactive_templates_schema :: list()
  def interactive_templates_schema do
    [
      %{
        description: "Unique ID for the interactive template",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "The label of the interactive message",
        name: "label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "The type of interactive message- quick_reply or list",
        name: "type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Interactive content of the message stored in form of json",
        name: "interactive_content",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Translation of interactive content stored in form of json",
        name: "translations",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "The language interactive message is created in",
        name: "language",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Field to check if title needs to be send in the interactive message",
        name: "send_with_title",
        type: "Boolean",
        mode: "REQUIRED"
      },
      %{
        description: "Tag added to the interactive message",
        name: "tag",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for the certificate templates table
  """
  @spec certificate_templates_schema :: list()
  def certificate_templates_schema do
    [
      %{
        description: "Unique ID for the certificate template",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "The label of the certificate template",
        name: "label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "The description of the certificate template",
        name: "description",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "The url of the certificate template",
        name: "url",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "The type of the template",
        name: "type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for the issued certificates table
  """
  @spec issued_certificates_schema :: list()
  def issued_certificates_schema do
    [
      %{
        description: "Unique ID for the certificate template",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "The ID of the certificate template used",
        name: "template_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "The label of the certificate template used",
        name: "template_label",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "The contact phone to which certificate was issued",
        name: "phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "The GCS url of the issued certificate",
        name: "gcs_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Error while issuing certificate, if any",
        name: "errors",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Procedure for flat fields
  """
  @spec flat_fields_procedure(String.t(), String.t()) :: String.t()
  def flat_fields_procedure(project_id, dataset_id) do
    """
      BEGIN
      EXECUTE IMMEDIATE
      '''
      CREATE OR REPLACE VIEW `#{project_id}.#{dataset_id}.flat_fields` AS SELECT id, (SELECT STRING_AGG(DISTINCT label) from UNNEST(`groups`)) AS group_category,
      '''
      || (
        SELECT STRING_AGG(DISTINCT "(SELECT value FROM UNNEST(fields) WHERE label = '" || label || "') AS " || REPLACE(label, ' ', '_')
        )
        FROM `#{project_id}.#{dataset_id}.contacts`, UNNEST(fields)
      ) || '''
      ,(SELECT MIN(inserted_at) FROM UNNEST(fields)) AS inserted_at,
      (SELECT MAX(inserted_at) FROM UNNEST(fields)) AS last_updated_at
      FROM `#{project_id}.#{dataset_id}.contacts`''';
      END;
    """
  end

  @doc """
  Schema for WhatsApp Forms table
  """
  @spec whatsapp_form_schema() :: list(map())
  def whatsapp_form_schema do
    [
      %{
        description: "Unique ID for the WhatsApp Form",
        name: "id",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Name of the WhatsApp Form",
        name: "name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Description of the WhatsApp Form",
        name: "description",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Unique ID for the WhatsApp Form generated by Meta",
        name: "meta_flow_id",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Status of the WhatsApp Form",
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Categories of the WhatsApp Form",
        name: "categories",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the WhatsApp Form was created",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the WhatsApp Form was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for WhatsApp Form Responses table
  """
  @spec whatsapp_form_response_schema() :: list(map())
  def whatsapp_form_response_schema do
    [
      %{
        description: "Unique ID for the WhatsApp Form Response",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Raw response data from the WhatsApp Form",
        name: "raw_response",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the form was submitted",
        name: "submitted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "ID of the WhatsApp Form",
        name: "whatsapp_form_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Name of the WhatsApp Form",
        name: "whatsapp_form_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Contact ID who submitted the form",
        name: "contact_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Phone number of the contact who submitted the form",
        name: "contact_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Name of the contact who submitted the form",
        name: "contact_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Unique UUID for the row (allows us to delete duplicates)",
        name: "bq_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end

  @doc """
  Schema for Trial user table
  """
  @spec trial_user_schema() :: list(map())
  def trial_user_schema do
    [
      %{
        description: "Unique ID for the Trial User",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Name of the trial user",
        name: "Username",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Email address of the trial user",
        name: "email",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Phone number of the trial user",
        name: "phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Organization name of the trial user",
        name: "organization_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "User entered the OTP or not",
        name: "OTP entered",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was first made",
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was last updated",
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        description: "Time when the record entry was made on bigquery",
        name: "bq_inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      }
    ]
  end
end
