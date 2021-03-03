defmodule Glific.BigqueryTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo
  use ExUnit.Case

  alias Glific.{
    Bigquery,
    Contacts,
    Fixtures,
    Jobs.BigQueryWorker,
    Messages,
    Partners,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()

    default_goth_json = """
    {
    "project_id": "DEFAULT PROJECT ID",
    "private_key_id": "DEFAULT API KEY",
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
      Bigquery.get_table_struct(table)
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
    BigQueryWorker.queue_table_data("messages", attrs.organization_id, @min_id, max_id)
    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "queue_table_data/4 should create job for messages_delta",
       %{global_schema: global_schema} = attrs do
    message = Fixtures.message_fixture(Map.merge(attrs, %{flow: :inbound}))
    Messages.update_message(message, %{body: "hello"})

    max_id = get_max_id("messages", attrs)
    BigQueryWorker.queue_table_data("messages_delta", attrs.organization_id, @min_id, max_id)
    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "queue_table_data/4 should create job for contacts",
       %{global_schema: global_schema} = attrs do
    max_id = get_max_id("contacts", attrs)
    BigQueryWorker.queue_table_data("contacts", attrs.organization_id, @min_id, max_id)
    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "queue_table_data/4 should create job for contacts_delta",
       %{global_schema: global_schema} = attrs do
    contact = Fixtures.contact_fixture()

    Contacts.update_contact(contact, %{
      name: "some updated name"
    })

    max_id = get_max_id("contacts", attrs)
    BigQueryWorker.queue_table_data("contacts", attrs.organization_id, @min_id, max_id)
    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "queue_table_data/4 should create job for flows",
       %{global_schema: global_schema} = attrs do
    max_id = get_max_id("flows", attrs)
    BigQueryWorker.queue_table_data("flows", attrs.organization_id, @min_id, max_id)
    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  test "queue_table_data/4 should create job for flow_results",
       %{global_schema: global_schema} = attrs do
    max_id = get_max_id("flow_results", attrs)
    BigQueryWorker.queue_table_data("flow_results", attrs.organization_id, @min_id, max_id)
    assert_enqueued(worker: BigQueryWorker, prefix: global_schema)
    Oban.drain_queue(queue: :bigquery)
  end

  @messages_query "MERGE `test_dataset.messages` target  USING ( SELECT * EXCEPT(row_num) FROM  ( SELECT *, ROW_NUMBER() OVER(PARTITION BY delta.id ORDER BY delta.updated_at DESC) AS row_num FROM `test_dataset.messages_delta` delta ) WHERE row_num = 1) source ON target.id = source.id WHEN MATCHED THEN UPDATE SET target.type = source.type,target.status = source.status,target.sent_at = source.sent_at,target.tags_label = source.tags_label,target.flow_label = source.flow_label,target.flow_name = source.flow_name,target.flow_uuid = source.flow_uuid;"

  @contact_query "MERGE `test_dataset.contacts` target  USING ( SELECT * EXCEPT(row_num) FROM  ( SELECT *, ROW_NUMBER() OVER(PARTITION BY delta.id ORDER BY delta.updated_at DESC) AS row_num FROM `test_dataset.contacts_delta` delta ) WHERE row_num = 1) source ON target.id = source.id WHEN MATCHED THEN UPDATE SET target.provider_status = source.provider_status,target.status = source.status,target.language = source.language,target.optin_time = source.optin_time,target.optout_time = source.optout_time,target.last_message_at = source.last_message_at,target.updated_at = source.updated_at,target.fields = source.fields,target.settings = source.settings,target.groups = source.groups,target.tags = source.tags;"

  @flow_results_query "MERGE `test_dataset.flow_results` target  USING ( SELECT * EXCEPT(row_num) FROM  ( SELECT *, ROW_NUMBER() OVER(PARTITION BY delta.id ORDER BY delta.updated_at DESC) AS row_num FROM `test_dataset.flow_results_delta` delta ) WHERE row_num = 1) source ON target.id = source.id WHEN MATCHED THEN UPDATE SET target.results = source.results;"

  test "generate_merge_query/2 create merge query for messages" do
    credentials = %{dataset_id: "test_dataset"}
    assert @messages_query == Bigquery.generate_merge_query("messages", credentials)
  end

  test "generate_merge_query/2 create merge query for contacts" do
    credentials = %{dataset_id: "test_dataset"}
    assert @contact_query == Bigquery.generate_merge_query("contacts", credentials)
  end

  test "generate_merge_query/2 create merge query for flow_results" do
    credentials = %{dataset_id: "test_dataset"}
    assert @flow_results_query == Bigquery.generate_merge_query("flow_results", credentials)
  end

  test "clean_delta_tables/2 should delete delta tables", attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 404,
          body: "{\"error\":{\"code\":404,\"status\":\"NOT_FOUND\"}}"
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

    credentials = %{dataset_id: "test_dataset", conn: conn, project_id: "test_project"}

    assert_raise RuntimeError, fn ->
      Bigquery.clean_delta_tables("demo_table", credentials, attrs.organization_id)
    end
  end

  @unix_time 1_464_096_368
  @formated_time "2016-05-24 18:56:08"
  test "format_date/2 should create job for contacts", attrs do
    {:ok, datetime} = DateTime.from_unix(@unix_time)
    assert nil == Bigquery.format_date(nil, attrs.organization_id)
    assert @formated_time == Bigquery.format_date(datetime, attrs.organization_id)

    assert @formated_time ==
             Bigquery.format_date(DateTime.to_string(datetime), attrs.organization_id)
  end

  test "format_update_fields/1 should string for preparing query" do
    assert "" ==
             Bigquery.format_update_fields([])

    assert "target.groups = source.groups" ==
             Bigquery.format_update_fields(["groups"])

    assert "target.groups = source.groups,target.tags = source.tags" ==
             Bigquery.format_update_fields(["groups", "tags"])
  end
end
