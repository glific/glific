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
        description: "Uniquely generated message UUID, primarily needed for the flow editor",
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
        description: "refrence ID for an HSM",
        name: "template_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "refrence ID for an interactive template",
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
        description: "ID of the message media table refrence to the message media table",
        name: "media_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "ID of the profile table refrence to the profile table",
        name: "profile_id",
        type: "INTEGER",
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
      }
    ]
  end

  @doc """
  Schema for flow context schema
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
        description: "contact id refrences to the contact table",
        name: "contact_id",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "contact phone refrences to the contact table",
        name: "contact_phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        description: "local result of a perticular flow context",
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
        description: "Parent flow context id refrences to the flow context table",
        name: "parent_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        description: "flow_broadcast_id refrences to the flow broadcast table",
        name: "flow_broadcast_id",
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
        description: "ID of the profile table refrence to the profile table",
        name: "profile_id",
        type: "INTEGER",
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
          "Unique ID of the flow; we store flows with both id and uuid, since floweditor always refers to a flow by its uuid ",
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
        description: "ID of the profile table refrence to the profile table",
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
          "Unique ID of the flow; we store flows with both id and uuid, since floweditor always refers to a flow by its uuid ",
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
        description: "JSON object for storing the recenet messages",
        name: "recent_messages",
        type: "STRING",
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
        description: "ID of the profile table refrence to the profile table",
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
        description: "Unique ID for the profile",
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "Conversation ID for the message",
        name: "conversation_id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        description: "deduction_type for the message conversation",
        name: "deduction_type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        description: "is_billable for the message conversation",
        name: "is_billable",
        type: "BOOLEAN",
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
        FROM `#{project_id}.#{dataset_id}.contacts`, unnest(fields)
      ) || '''
      ,(SELECT MIN(inserted_at) FROM UNNEST(fields)) AS inserted_at,
      (SELECT MAX(inserted_at) FROM UNNEST(fields)) AS last_updated_at
      FROM `#{project_id}.#{dataset_id}.contacts`''';
      END;
    """
  end
end
