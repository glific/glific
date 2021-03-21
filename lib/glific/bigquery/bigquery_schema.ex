defmodule Glific.BigquerySchema do
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
        description: "'Options : Sent, Delivered or Read'",
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
        mode: "REQUIRED"
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
        mode: "REQUIRED"
      },
      %{
        description: "ID of the flow context with which the user is associated to in the flow",
        name: "flow_context_id",
        type: "INTEGER",
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
      CREATE OR REPLACE VIEW `#{project_id}.#{dataset_id}.flat_fields` AS SELECT id, (SELECT label from UNNEST(`groups`)) AS group_category,
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
