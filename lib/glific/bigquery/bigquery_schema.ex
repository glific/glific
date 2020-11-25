defmodule Glific.BigquerySchema do
  @moduledoc """
  Schema for tables to be created for a dataset
  """

  @doc """
  Schema for contact table
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
  Schema for contact table
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
      }
    ]
  end

  @doc """
  Schema for contact table
  """
  @spec flow_schema :: list()
  def flow_schema do
    [
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
        name: "revision_number",
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
        name: "status",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "keywords",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
          %{
            name: "keyword",
            type: "STRING",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        name: "flow_revision",
        type: "RECORD",
        mode: "REPEATED",
        fields: [
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
      }
    ]
  end
end
