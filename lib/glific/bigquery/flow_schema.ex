defmodule Glific.FlowSchema do
  @moduledoc """
  Schema for flows
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
        name: "revision number",
        type: "STRING",
        mode: "REQUIRED"
      },
      %{
        name: "keywords",
        type: "RECORD",
        mode: "NULLABLE",
        fields: [
          %{
            name: "keyword",
            type: "STRING",
            mode: "NULLABLE"
          }
        ]
      },
      %{
        name: "flow revision",
        type: "RECORD",
        mode: "NULLABLE",
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
