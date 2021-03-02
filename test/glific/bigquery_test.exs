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
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
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
