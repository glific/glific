defmodule Glific.BigQuery.InstrumentationTest do
  @moduledoc false
  use Glific.DataCase
  import Mock

  alias Glific.BigQuery.Instrumentation

  # Appsignal.increment_counter/3 is a no-op NIF call in test, so the assertions capture the
  # arguments instead — the tag values are the contract an alert is built on.
  defp capture_counters(fun) do
    parent = self()

    with_mock Appsignal,
      increment_counter: fn name, value, tags ->
        send(parent, {:counter, name, value, tags})
        :ok
      end do
      fun.()
    end

    collect([])
  end

  defp collect(acc) do
    receive do
      {:counter, name, value, tags} -> collect([{name, value, tags} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  describe "record/4" do
    test "emits bigquery_sync_count tagged with table, action, status and org" do
      counters =
        capture_counters(fn ->
          Instrumentation.record("messages", :success, :insert, 1)
        end)

      assert [{"bigquery_sync_count", 1, tags}] = counters
      assert tags.table == "messages"
      assert tags.action == "insert"
      assert tags.status == "success"
      assert tags.organization_id == "1"
    end

    test "tags each table distinctly so one broken table is not masked by healthy ones" do
      counters =
        capture_counters(fn ->
          Instrumentation.record("messages", :success, :insert, 1)
          Instrumentation.record("contacts", :permission_denied, :update, 1)
          Instrumentation.record("flow_results", :timeout, :insert, 2)
        end)

      assert Enum.map(counters, fn {_name, _value, tags} -> {tags.table, tags.status} end) == [
               {"messages", "success"},
               {"contacts", "permission_denied"},
               {"flow_results", "timeout"}
             ]

      assert Enum.map(counters, fn {_name, _value, tags} -> tags.organization_id end) ==
               ["1", "1", "2"]
    end

    test "records every failure status the sync can produce" do
      for status <- [:schema_not_found, :permission_denied, :timeout, :exception] do
        counters =
          capture_counters(fn -> Instrumentation.record("messages", status, :insert, 1) end)

        assert [{"bigquery_sync_count", 1, tags}] = counters
        assert tags.status == Atom.to_string(status)
      end
    end

    test "never propagates a metrics failure into the sync" do
      with_mock Appsignal, increment_counter: fn _n, _v, _t -> raise "appsignal down" end do
        assert :ok == Instrumentation.record("messages", :success, :insert, 1)
      end
    end
  end

  describe "handle_insert_query_response/3 integration" do
    test "counts PERMISSION_DENIED as a failure even though it never raises" do
      # This is the case a perform/1 wrapper alone would report as success: the credential
      # is disabled and the sync is dead, but nothing raises and nothing returns an error.
      counters =
        capture_counters(fn ->
          Glific.BigQuery.handle_insert_query_response(
            {:error,
             %{
               body:
                 ~s({"error":{"code":403,"status":"PERMISSION_DENIED","errors":[{"message":"denied"}]}})
             }},
            1,
            table: "messages",
            action: :insert,
            max_id: 10
          )
        end)

      assert Enum.any?(counters, fn {name, _v, tags} ->
               name == "bigquery_sync_count" and tags.table == "messages" and
                 tags.status == "permission_denied"
             end),
             "expected a permission_denied counter, got #{inspect(counters)}"
    end

    test "counts a successful insert" do
      counters =
        capture_counters(fn ->
          Glific.BigQuery.handle_insert_query_response(
            {:ok, %{insertErrors: nil}},
            1,
            table: "contacts",
            action: :insert,
            max_id: 10
          )
        end)

      assert Enum.any?(counters, fn {name, _v, tags} ->
               name == "bigquery_sync_count" and tags.table == "contacts" and
                 tags.status == "success"
             end),
             "expected a success counter, got #{inspect(counters)}"
    end
  end

  describe "make_job_to_remove_duplicate/2" do
    test "counts a failed dedup as error, not success" do
      # handle_duplicate_removal_job_error/4 logs the failure and returns without raising,
      # so a caller that records success after calling it would report green for a dedup
      # that never ran.
      counters =
        capture_counters(fn ->
          Glific.BigQuery.handle_duplicate_removal_job_error(
            {:error, "boom"},
            "messages",
            %{},
            1
          )
        end)

      assert Enum.any?(counters, fn {name, _v, tags} ->
               name == "bigquery_sync_count" and tags.table == "messages" and
                 tags.action == "remove_duplicates" and tags.status == "error"
             end),
             "expected an error counter, got #{inspect(counters)}"
    end

    test "counts a successful dedup" do
      counters =
        capture_counters(fn ->
          Glific.BigQuery.handle_duplicate_removal_job_error({:ok, %{}}, "contacts", %{}, 1)
        end)

      assert Enum.any?(counters, fn {name, _v, tags} ->
               name == "bigquery_sync_count" and tags.table == "contacts" and
                 tags.action == "remove_duplicates" and tags.status == "success"
             end),
             "expected a success counter, got #{inspect(counters)}"
    end
  end

  describe "track/4" do
    test "does not emit a counter when the work succeeds" do
      counters =
        capture_counters(fn ->
          assert :ok == Instrumentation.track("messages", :insert, 1, fn -> :ok end)
        end)

      # The success counter comes from handle_insert_query_response/3, where the BigQuery
      # outcome is actually known. track/4 only covers the raising paths, so counting here
      # too would double every successful sync.
      assert counters == []
    end

    test "records exception and re-raises so Oban still sees the failure" do
      counters =
        capture_counters(fn ->
          assert_raise RuntimeError, "boom", fn ->
            Instrumentation.track("contacts", :update, 3, fn -> raise "boom" end)
          end
        end)

      assert [{"bigquery_sync_count", 1, tags}] = counters
      assert tags.table == "contacts"
      assert tags.action == "update"
      assert tags.status == "exception"
      assert tags.organization_id == "3"
    end
  end
end
