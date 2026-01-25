defmodule Glific.BigQueryTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo
  use ExUnit.Case
  import Mock

  alias Glific.{
    BigQuery,
    BigQuery.BigQueryJob,
    BigQuery.BigQueryWorker,
    Contacts.Contact,
    Flows.FlowResult,
    Partners,
    Seeds.SeedsDev
  }

  setup_with_mocks([
    {
      Goth.Token,
      [:passthrough],
      [
        for_scope: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ]
    }
  ]) do
    %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}
  end

  setup do
    organization = SeedsDev.seed_organizations()

    default_goth_json = """
    {
    "project_id": "DEFAULTPROJECTID",
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
    with_mocks([
      {
        Goth.Token,
        [:passthrough],
        [
          fetch: fn _url ->
            {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
          end
        ]
      }
    ]) do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200
          }
      end)

      assert :ok == BigQuery.make_job_to_remove_duplicate("messages", attrs.organization_id)
    end
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
        [
          fetch: fn _url ->
            {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
          end
        ]
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
  WHERE struct(id, updated_at, bq_uuid) IN (
    SELECT STRUCT(id, updated_at, bq_uuid)  FROM (
      SELECT id, updated_at, bq_uuid, ROW_NUMBER() OVER (
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

  test "handle_sync_errors/2 return ok atom when status is not ALREADY_EXISTS", attrs do
    error = %{
      "error" => %{
        "code" => 404,
        "status" => "NOT_FOUND"
      }
    }

    assert {:error, error} =
             BigQuery.handle_sync_errors(
               %{body: Jason.encode!(error)},
               attrs.organization_id,
               attrs
             )

    assert error == "Account deactivated with error code 404 status NOT_FOUND"
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
    with_mock(
      Goth.Token,
      [],
      fetch: fn _url ->
        {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
      end
    ) do
      assert {:ok, value} = BigQuery.fetch_bigquery_credentials(attrs.organization_id)
      assert true == is_map(value)
    end
  end

  test "fetch_bigquery_credentials/2 should return nil and disable credentials", attrs do
    with_mocks([
      {
        Goth.Token,
        [:passthrough],
        [
          fetch: fn _url ->
            {:error,
             "Could not retrieve token, response: {\"error\":\"invalid_grant\",\"error_description\":\"Invalid grant: account not found\"}"}
          end
        ]
      }
    ]) do
      Glific.Caches.remove(attrs.organization_id, [{:provider_token, "bigquery"}])
      assert {:error, error} = BigQuery.fetch_bigquery_credentials(attrs.organization_id)
      assert error == "Error fetching token with Service Account JSON"

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
  @formatted_time "2016-05-24 18:56:08"
  test "format_date/2 should create job for contacts", attrs do
    {:ok, datetime} = DateTime.from_unix(@unix_time)
    assert nil == BigQuery.format_date(nil, attrs.organization_id)
    assert @formatted_time == BigQuery.format_date(datetime, attrs.organization_id)

    assert @formatted_time ==
             BigQuery.format_date(DateTime.to_string(datetime), attrs.organization_id)

    # There are cases where we get date as a iso date only type, so handling that too
    assert "#{String.split(@formatted_time, " ") |> List.first()} 00:00:00" ==
             BigQuery.format_date(DateTime.to_date(datetime) |> to_string, attrs.organization_id)
  end

  test "queue_table_data/3 should process and queue data correctly", %{organization_id: org_id} do
    with_mocks([
      {
        Goth.Token,
        [:passthrough],
        [
          fetch: fn _url ->
            {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
          end
        ]
      }
    ]) do
      url =
        "https://bigquery.googleapis.com/bigquery/v2/projects/DEFAULTPROJECTID/datasets/917834811114/tables/contacts/insertAll"

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post, url: ^url} ->
          %Tesla.Env{
            status: 200,
            body:
              Poison.encode!(%GoogleApi.BigQuery.V2.Model.TableDataInsertAllResponse{
                kind: "bigquery#tableDataInsertAllResponse",
                insertErrors: nil
              })
          }
      end)

      result = BigQueryWorker.queue_table_data("contacts", org_id, %{some_attr: "value"})
      assert result == :ok
    end
  end

  test "queue_table_data/3 should process and skip simulator contacts, ensuring table_id should be updated for flow_results table" do
    with_mocks([
      {
        Goth.Token,
        [:passthrough],
        [
          fetch: fn _url ->
            {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
          end
        ]
      }
    ]) do
      url =
        "https://bigquery.googleapis.com/bigquery/v2/projects/DEFAULTPROJECTID/datasets/917834811114/tables/contacts/insertAll"

      Tesla.Mock.mock(fn
        %Tesla.Env{method: :post, url: ^url} ->
          %Tesla.Env{
            status: 200,
            body:
              Poison.encode!(%GoogleApi.BigQuery.V2.Model.TableDataInsertAllResponse{
                kind: "bigquery#tableDataInsertAllResponse",
                insertErrors: nil
              })
          }
      end)

      org_id = 1

      # check the table id before syncing the flow_results table
      job_before =
        BigQueryJob
        |> where([b], b.organization_id == ^org_id and b.table == "flow_results")
        |> Repo.one()

      initial_table_id = job_before.table_id

      # add the simulator contact's entry only in the flow results
      phone = "9876543210_1"
      {:ok, contact} = Repo.fetch_by(Contact, %{phone: phone})

      Repo.delete_all(
        from fr in FlowResult,
          where: fr.organization_id == ^org_id
      )

      1..100
      |> Enum.each(fn _ ->
        Repo.insert!(%FlowResult{
          results: %{language: %{input: Enum.random(0..10), category: "English"}},
          contact_id: contact.id,
          flow_id: 1,
          flow_uuid: Ecto.UUID.generate(),
          flow_version: 1,
          organization_id: org_id
        })
      end)

      job = %Oban.Job{
        args: %{
          "table" => "flow_results",
          "organization_id" => org_id,
          "action" => "insert"
        }
      }

      BigQueryWorker.perform(job)

      job_after =
        BigQueryJob
        |> where([b], b.organization_id == ^org_id and b.table == "flow_results")
        |> Repo.one()

      assert job_after.table_id != initial_table_id
    end
  end
end
