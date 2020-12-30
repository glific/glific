defmodule Glific.Bigquery do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  alias Glific.{
    BigquerySchema,
    Partners,
    Repo
  }

  alias GoogleApi.BigQuery.V2.{
    Api.Datasets,
    Api.Jobs,
    Api.Routines,
    Api.Tables,
    Connection
  }

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec bigquery_dataset(String.t(), non_neg_integer) :: :ok
  def bigquery_dataset(dataset_id, organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["bigquery"]
    |> case do
      nil ->
        nil

      credentials ->
        {:ok, secrets} = Jason.decode(credentials.secrets["service_account"])
        project_id = secrets["project_id"]
        token = Partners.get_goth_token(organization_id, "bigquery")
        conn = Connection.new(token.token)

        case create_dataset(conn, project_id, dataset_id) do
          {:ok, _} ->
            create_tables(conn, dataset_id, project_id)
            contacts_messages_view(conn, dataset_id, project_id)
            flat_fields_procedure(conn, dataset_id, project_id)

          {:error, response} ->
            {:ok, data} = Jason.decode(response.body)
            handle_response(data, conn, dataset_id, project_id, organization_id)
        end
    end

    :ok
  end

  defp create_tables(conn, dataset_id, project_id) do
    table(BigquerySchema.contact_schema(), conn, dataset_id, project_id, "contacts")
    table(BigquerySchema.message_schema(), conn, dataset_id, project_id, "messages")
    table(BigquerySchema.flow_schema(), conn, dataset_id, project_id, "flows")
    table(BigquerySchema.flow_result_schema(), conn, dataset_id, project_id, "flow_results")
  end

  defp handle_response(data, conn, dataset_id, project_id, organization_id) do
    error = data["error"]

    if error["status"] == "ALREADY_EXISTS" do
      create_tables(conn, dataset_id, project_id)
      alter_bigquery_tables(dataset_id, organization_id)
    end
  end

  @doc """
  Alter bigquery table schema,
  if required this function should be called from iex
  """
  @spec alter_bigquery_tables(String.t(), non_neg_integer) :: :ok
  def alter_bigquery_tables(dataset_id, organization_id) do
    organization = Partners.organization(organization_id)

    credentials = organization.services["bigquery"]

    {:ok, secrets} = Jason.decode(credentials.secrets["service_account"])
    project_id = secrets["project_id"]
    token = Partners.get_goth_token(organization_id, "bigquery")
    conn = Connection.new(token.token)

    case Datasets.bigquery_datasets_get(conn, project_id, dataset_id) do
      {:ok, _} ->
        alter_table(BigquerySchema.contact_schema(), conn, dataset_id, project_id, "contacts")
        alter_table(BigquerySchema.message_schema(), conn, dataset_id, project_id, "messages")
        alter_table(BigquerySchema.flow_schema(), conn, dataset_id, project_id, "flows")
        alter_table(BigquerySchema.flow_schema(), conn, dataset_id, project_id, "flow_results")
        alter_contacts_messages_view(conn, dataset_id, project_id)

      {:error, _} ->
        nil
    end

    :ok
  end

  @doc """
    Updating existing field in a table
  """
  @spec update_contact(non_neg_integer, map(), non_neg_integer) :: :ok
  def update_contact(phone_no, updated_fields, organization_id) do
    organization = Partners.organization(organization_id) |> Repo.preload(:contact)
    dataset_id = organization.contact.phone

    organization.services["bigquery"]
    |> case do
      nil ->
        nil

      credentials ->
        {:ok, secrets} = Jason.decode(credentials.secrets["service_account"])
        project_id = secrets["project_id"]

        updated_values =
          Enum.reduce(updated_fields, %{}, fn {key, field}, acc ->
            Map.put(acc, key, format_field_values(key, field, organization_id))
          end)

        sql =
          "UPDATE `#{dataset_id}.contacts` SET #{format_update_values(updated_values)} WHERE phone= '#{
            phone_no
          }'"

        token = Partners.get_goth_token(organization_id, "bigquery")
        conn = Connection.new(token.token)

        Jobs.bigquery_jobs_query(conn, project_id, body: %{query: sql, useLegacySql: false})
        |> case do
          {:ok, response} -> response
          {:error, _} -> nil
        end
    end

    :ok
  end

  defp format_field_values("fields", contact_fields, org_id) when is_map(contact_fields) do
    contact_fields = validate_fields(contact_fields)

    values =
      Enum.map(contact_fields, fn contact_field ->
        contact_field = Glific.atomize_keys(contact_field)

        "('#{contact_field.label}', '#{contact_field.value}', '#{contact_field.type}', '#{
          format_date(contact_field.inserted_at, org_id)
        }')"
      end)

    "[STRUCT<label STRING, value STRING, type STRING, inserted_at DATETIME>#{
      Enum.join(values, ",")
    }]"
  end

  defp format_field_values(_key, field, _org_id), do: field

  @spec validate_fields(map()) :: list()
  defp validate_fields(contact_fields) do
    contact_fields
    |> Map.values()
    |> Enum.reject(fn field ->
      [:value, :label, :inserted_at, :type]
      |> Enum.all?(&Map.has_key?(Glific.atomize_keys(field), &1)) == false
    end)
  end

  @spec format_date(DateTime.t() | nil, non_neg_integer()) :: any()
  defp format_date(nil, _),
    do: nil

  defp format_date(date, organization_id) when is_binary(date) do
    timezone = Partners.organization(organization_id).timezone

    Timex.parse(date, "{RFC3339z}")
    |> elem(1)
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{M}-{D} {h24}:{m}:{s}")
  end

  defp format_date(date, organization_id) do
    timezone = Partners.organization(organization_id).timezone

    date
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{M}-{D} {h24}:{m}:{s}")
  end

  defp format_update_values(values) do
    Map.keys(values)
    |> Enum.map(fn key ->
      if key == "fields" do
        " #{key} = #{values[key]}"
      else
        " #{key} = #{get_key(values[key])}"
      end
    end)
    |> Enum.join(",")
  end

  defp get_key(value) when is_binary(value), do: "'#{value}'"
  defp get_key(value), do: value

  defp create_dataset(conn, project_id, dataset_id) do
    Datasets.bigquery_datasets_insert(
      conn,
      project_id,
      [
        body: %{
          datasetReference: %{
            datasetId: dataset_id,
            projectId: project_id
          }
        }
      ],
      []
    )
  end

  defp table(schema, conn, dataset_id, project_id, table_id) do
    Tables.bigquery_tables_insert(
      conn,
      project_id,
      dataset_id,
      [
        body: %{
          tableReference: %{
            datasetId: dataset_id,
            projectId: project_id,
            tableId: table_id
          },
          schema: %{
            fields: schema
          }
        }
      ],
      []
    )
  end

  defp alter_table(schema, conn, dataset_id, project_id, table_id) do
    Tables.bigquery_tables_update(
      conn,
      project_id,
      dataset_id,
      table_id,
      [
        body: %{
          tableReference: %{
            datasetId: dataset_id,
            projectId: project_id,
            tableId: table_id
          },
          schema: %{
            fields: schema
          }
        }
      ],
      []
    )
  end

  @doc """
  Creating a view with unnested fields from contacts 
  """
  @spec flat_fields_procedure(String.t(), non_neg_integer) :: :ok
  defp flat_fields_procedure(conn, dataset_id, project_id) do 
    {:ok, response} = 
      Routines.bigquery_routines_insert(
        conn,
        project_id,
        dataset_id,
        [
          body: %{
            routineReference: %{
              routineId: "flat_fields",
              datasetId: dataset_id,
              projectId: project_id
            },
            routineType: "PROCEDURE",
            definitionBody: 
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
            """, 
          }
        ],
        []
      )
    response
  end

  defp contacts_messages_view(conn, dataset_id, project_id) do
    {:ok, response} =
      Tables.bigquery_tables_insert(
        conn,
        project_id,
        dataset_id,
        [
          body: %{
            tableReference: %{
              datasetId: dataset_id,
              projectId: project_id,
              tableId: "contacts_messages"
            },
            view: %{
              query:
                "SELECT messages.id, contact_phone, phone, name, optin_time, language, flow_label, messages.tags_label, messages.inserted_at, media_url
              FROM `#{project_id}.#{dataset_id}.messages` as messages
              JOIN `#{project_id}.#{dataset_id}.contacts` as contacts
              ON messages.contact_phone = contacts.phone",
              useLegacySql: false
            }
          }
        ],
        []
      )

    response
  end

  defp alter_contacts_messages_view(conn, dataset_id, project_id) do
    {:ok, response} =
      Tables.bigquery_tables_update(
        conn,
        project_id,
        dataset_id,
        "contacts_messages",
        [
          body: %{
            tableReference: %{
              datasetId: dataset_id,
              projectId: project_id,
              tableId: "contacts_messages"
            },
            view: %{
              query:
                "SELECT messages.id, uuid, contact_phone, phone, name, optin_time, language, flow_label, messages.tags_label, messages.inserted_at, media_url
              FROM `#{project_id}.#{dataset_id}.messages` as messages
              JOIN `#{project_id}.#{dataset_id}.contacts` as contacts
              ON messages.contact_phone = contacts.phone",
              useLegacySql: false
            }
          }
        ],
        []
      )

    response
  end
end