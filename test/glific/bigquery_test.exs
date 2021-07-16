defmodule Glific.BigQueryTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo
  use ExUnit.Case
  import Mock

  alias Glific.{
    BigQuery,
    BigQuery.BigQueryWorker,
    Partners,
    Seeds.SeedsDev
  }

  setup_with_mocks([
    {
      Goth.Token,
      [:passthrough],
      [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
    }
  ]) do
    %{token: "0xFAKETOKEN_Q="}
  end

  setup do
    organization = SeedsDev.seed_organizations()

    default_goth_json = """
    {
    "project_id": "DEFAULT PROJECT ID",
    "private_key_id": "DEFAULT API KEY",
    "client_email": "DEFAULT CLIENT EMAIL",
    "private_key": "DEFAULT PRIVATE KEY"
    }
    """

    valid_attrs = %{
      secrets: %{"service_account" => default_goth_json},
      is_active: true,
      shortcode: "bigquery",
      organization_id: organization.id
    }

    {:ok, _credential} = Partners.create_credential(valid_attrs)
    SeedsDev.seed_contacts(organization)
    SeedsDev.seed_messages()
    SeedsDev.seed_flows()
    SeedsDev.seed_flow_results(organization)
    :ok
  end

  @max_id 100
  @min_id 0

  defp get_max_id(table, attrs) do
    data =
      BigQuery.get_table_struct(table)
      |> select([m], m.id)
      |> where([m], m.organization_id == ^attrs.organization_id)
      |> order_by([m], asc: m.id)
      |> limit(100)
      |> Repo.all()

    if is_list(data), do: List.last(data), else: @max_id
  end

  test "queue_table_data/4 should create job for messages",
       %{global_schema: global_schema} = attrs do
    max_id = get_max_id("messages", attrs)

    BigQueryWorker.queue_table_data("messages", attrs.organization_id, %{
      min_id: @min_id,
      max_id: max_id
    })

    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "queue_table_data/4 should create job for contacts",
       %{global_schema: global_schema} = attrs do
    max_id = get_max_id("contacts", attrs)

    BigQueryWorker.queue_table_data("contacts", attrs.organization_id, %{
      min_id: @min_id,
      max_id: max_id
    })

    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "queue_table_data/4 should create job for flows",
       %{global_schema: global_schema} = attrs do
    max_id = get_max_id("flows", attrs)

    BigQueryWorker.queue_table_data("flows", attrs.organization_id, %{
      min_id: @min_id,
      max_id: max_id
    })

    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "queue_table_data/4 should create job for flow_results",
       %{global_schema: global_schema} = attrs do
    max_id = get_max_id("flow_results", attrs)

    BigQueryWorker.queue_table_data("flow_results", attrs.organization_id, %{
      min_id: @min_id,
      max_id: max_id
    })

    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "periodic_updates/4 should create job for to remove duplicate contact",
       %{global_schema: global_schema} = attrs do
    BigQueryWorker.periodic_updates(attrs.organization_id)
    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "handle_insert_query_response/3 should deactivate bigquery credentials", attrs do
    BigQuery.handle_insert_query_response(
      {:error, %{body: "{\"error\":{\"code\":404,\"status\":\"PERMISSION_DENIED\"}}"}},
      attrs.organization_id,
      table: "messages",
      max_id: 10
    )

    {:ok, credential} = Partners.get_credential(%{organization_id: 1, shortcode: "bigquery"})
    assert false == credential.is_active
  end

  test "make_job_to_remove_duplicate/2 should delete duplicate messages", attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200
        }
    end)

    assert :ok == BigQuery.make_job_to_remove_duplicate("messages", attrs.organization_id)
  end

  test "make_job_to_remove_duplicate/2 should raise info log", attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200
        }
    end)

    with_mocks([
      {
        Goth.Token,
        [:passthrough],
        [for_scope: fn _url -> {:ok, %{token: "0xFAKETOKEN_Q="}} end]
      }
    ]) do
      # we'll need to figure out how to check if this did the right thing
      # making sure the log message is printed is quite useless
      BigQuery.make_job_to_remove_duplicate("messages", attrs.organization_id)
    end
  end

  test "handle_insert_query_response/3 should raise error", attrs do
    assert_raise RuntimeError, fn ->
      BigQuery.handle_insert_query_response(
        {:error, %{body: "{\"error\":{\"code\":404,\"status\":\"UNKNOWN_ERROR\"}}"}},
        attrs.organization_id,
        table: "messages",
        max_id: 10
      )


    end
  end

  @delete_query """
  DELETE FROM `test_dataset.messages`
  WHERE struct(id, updated_at) IN (
    SELECT STRUCT(id, updated_at)  FROM (
      SELECT id, updated_at, ROW_NUMBER() OVER (
        PARTITION BY delta.id ORDER BY delta.updated_at DESC
      ) AS rn
      FROM `test_dataset.messages` delta
      WHERE updated_at < DATETIME(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 HOUR),
        'Asia/Kolkata')) a WHERE a.rn <> 1 ORDER BY id);
  """

  test "generate_duplicate_removal_query/3 should create sql query", attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: "{\"clear\":{\"code\":200,\"status\":\"TABLE_CREATED\"}}"
        }
    end)

    conn = %Tesla.Client{
      adapter: nil,
      fun: nil,
      post: [],
      pre: [
        {Tesla.Middleware.Headers, :call,
         [
           [
             {"authorization", "Bearer ya29.c.Kp0B9Acz3QK1"}
           ]
         ]}
      ]
    }

    assert @delete_query ==
             BigQuery.generate_duplicate_removal_query(
               "messages",
               %{conn: conn, project_id: "test_project", dataset_id: "test_dataset"},
               attrs.organization_id
             )
  end

  test "handle_insert_query_response/3 should update table", attrs do
    job_table1 = Glific.Jobs.get_bigquery_job(attrs.organization_id, "messages")

    BigQuery.handle_insert_query_response(
      {:ok, %{insertErrors: nil}},
      attrs.organization_id,
      table: "messages",
      max_id: 10
    )

    job_table2 = Glific.Jobs.get_bigquery_job(attrs.organization_id, "messages")
    assert job_table2.table_id > job_table1.table_id

    assert_raise RuntimeError, fn ->
      BigQuery.handle_insert_query_response(
        {:ok, %{insertErrors: %{error: "Some errors"}}},
        attrs.organization_id,
        table: "messages",
        max_id: 10
      )
    end

    assert :ok ==
             BigQuery.handle_insert_query_response(
               {:ok, %{insertErrors: nil}},
               attrs.organization_id,
               table: "messages",
               max_id: nil
             )
  end

  test "handle_sync_errors/2 should raise error", attrs do
    assert_raise ArgumentError, fn ->
      BigQuery.handle_sync_errors(
        {:error, "error"},
        attrs.organization_id,
        attrs
      )
    end
  end

  test "handle_sync_errors/2 return ok atom when status is not ALREADY_EXISTS", attrs do
    assert :ok ==
             BigQuery.handle_sync_errors(
               %{body: "{\"error\":{\"code\":404,\"status\":\"NOT_FOUND\"}}"},
               attrs.organization_id,
               attrs
             )
  end

  test "handle_sync_errors/2 should raise error when status is not ALREADY_EXISTS", attrs do
    assert_raise RuntimeError, fn ->
      BigQuery.handle_sync_errors(
        %{body: ""},
        attrs.organization_id,
        attrs
      )
    end
  end

  test "fetch_bigquery_credentials/2 should return credentials in ok tuple format", attrs do
    assert {:ok, value} = BigQuery.fetch_bigquery_credentials(attrs.organization_id)
    assert true == is_map(value)
  end

  test "fetch_bigquery_credentials/2 should return nil and disable credentials", attrs do
    with_mocks([
      {
        Goth.Token,
        [:passthrough],
        [
          for_scope: fn _url ->
            {:error,
             "Could not retrieve token, response: {\"error\":\"invalid_grant\",\"error_description\":\"Invalid grant: account not found\"}"}
          end
        ]
      }
    ]) do
      assert true = is_nil(BigQuery.fetch_bigquery_credentials(attrs.organization_id))

      {:ok, cred} =
        Partners.get_credential(%{organization_id: attrs.organization_id, shortcode: "bigquery"})

      assert cred.is_active == false
    end
  end

  test "handle_duplicate_removal_job_error/2 should log info on successful deletion",
       attrs do
    # we need to figure out how to check that this function did the right thing
    BigQuery.handle_duplicate_removal_job_error(
      {:ok, "successful"},
      "messages",
      %{},
      attrs.organization_id
    )
  end

  test "create_tables/3 should create tables" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: "{\"clear\":{\"code\":200,\"status\":\"TABLE_CREATED\"}}"
        }
    end)

    conn = %Tesla.Client{
      adapter: nil,
      fun: nil,
      post: [],
      pre: [
        {Tesla.Middleware.Headers, :call,
         [
           [
             {"authorization", "Bearer ya29.c.Kp0B9Acz3QK1"}
           ]
         ]}
      ]
    }

    assert :ok == BigQuery.create_tables(conn, 1, "test_dataset", "test_table")
  end

  test "alter_tables/3 should throw error tables" do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          headers: [
            {"x-goog-api-client", "gl-elixir/1.10.4 gax/0.4.0 gdcl/0.47.0"},
            {"authorization", "Bearer ya29.c.Kp0B9Acz3QK1"}
          ],
          method: :get,
          url:
            "https://bigquery.googleapis.com/bigquery/v2/projects/test_table/datasets/test_dataset"
        }
    end)

    conn = %Tesla.Client{
      adapter: nil,
      fun: nil,
      post: [],
      pre: [
        {Tesla.Middleware.Headers, :call,
         [
           [
             {"authorization", "Bearer ya29.c.Kp0B9Acz3QK1"}
           ]
         ]}
      ]
    }

    assert :ok == BigQuery.alter_tables(conn, 1, "test_dataset", "test_table")
  end

  @unix_time 1_464_096_368
  @formated_time "2016-05-24 18:56:08"
  test "format_date/2 should create job for contacts", attrs do
    {:ok, datetime} = DateTime.from_unix(@unix_time)
    assert nil == BigQuery.format_date(nil, attrs.organization_id)
    assert @formated_time == BigQuery.format_date(datetime, attrs.organization_id)

    assert @formated_time ==
             BigQuery.format_date(DateTime.to_string(datetime), attrs.organization_id)
  end
end
