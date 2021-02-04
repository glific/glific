defmodule Glific.BigquerySchema do
  @moduledoc """
  Schema for tables to be created for a dataset
  """

  @doc """
  Schema for contacts table
  """
  @spec contact_schema :: list()
  def contact_schema do
    [
      %{
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        name: "name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "provider_status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "language",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "optin_time",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "optout_time",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "last_message_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "fields",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            name: "label",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            name: "value",
            type: "string",
            mode: "NULLABLE"
          },
          %{
            name: "type",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            name: "inserted_at",
            type: "DATETIME",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        name: "settings",
        type: "RECORD",
        mode: "NULLABLE",
        fields: [
          %{
            name: "label",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
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
        name: "groups",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            name: "label",
            type: "STRING",
            mode: "REQUIRED"
          },
          %{
            name: "description",
            type: "STRING",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        name: "tags",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            name: "label",
            type: "STRING",
            mode: "REQUIRED"
          }
        ]
      }
    ]
  end

  @spec contact_delta_schema :: list()
  def contact_delta_schema do
    [
      %{
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        name: "phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "provider_status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "language",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "optin_time",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "optout_time",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "last_message_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "updated_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "fields",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            name: "label",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            name: "value",
            type: "string",
            mode: "NULLABLE"
          },
          %{
            name: "type",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
            name: "inserted_at",
            type: "DATETIME",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        name: "settings",
        type: "RECORD",
        mode: "NULLABLE",
        fields: [
          %{
            name: "label",
            type: "STRING",
            mode: "NULLABLE"
          },
          %{
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
        name: "groups",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            name: "label",
            type: "STRING",
            mode: "REQUIRED"
          },
          %{
            name: "description",
            type: "STRING",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        name: "tags",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
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
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        name: "uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "body",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "flow",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "errors",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "sender_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "receiver_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "contact_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "contact_name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "user_phone",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "user_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "media_url",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "sent_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "inserted_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "tags_label",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "flow_label",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "flow_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "flow_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "longitude",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "latitude",
        type: "STRING",
        mode: "NULLABLE"
      }
    ]
  end

  @spec message_delta_schema :: list()
  def message_delta_schema do
    [
      %{
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        name: "type",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "contact_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "sent_at",
        type: "DATETIME",
        mode: "NULLABLE"
      },
      %{
        name: "tags_label",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "flow_label",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "flow_name",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
        name: "flow_uuid",
        type: "STRING",
        mode: "NULLABLE"
      },
      %{
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
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        name: "name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "uuid",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        name: "keywords",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
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
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        name: "name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "uuid",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "inserted_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        name: "updated_at",
        type: "DATETIME",
        mode: "REQUIRED"
      },
      %{
        name: "results",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "flow_version",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "contact_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "contact_name",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "flow_context_id",
        type: "INTEGER",
        mode: "NULLABLE"
      }
    ]
  end

  @spec flow_result_delta_schema :: list()
  def flow_result_delta_schema do
    [
      %{
        name: "id",
        type: "INTEGER",
        mode: "REQUIRED"
      },
      %{
        name: "uuid",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "contact_phone",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "results",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "flow_context_id",
        type: "INTEGER",
        mode: "NULLABLE"
      },
      %{
        name: "updated_at",
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
