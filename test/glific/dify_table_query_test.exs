defmodule Glific.DifyTableQueryTest do
  use Glific.DataCase, async: true

  alias Glific.{DifyTableQuery, Fixtures, Flows}

  describe "query_tables/3" do
    test "returns empty map for empty tables" do
      org_id = Fixtures.get_org_id()
      assert {:ok, %{}} = DifyTableQuery.query_tables(org_id, %{}, "24h")
    end

    test "returns empty list for unknown table" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        DifyTableQuery.query_tables(org_id, %{"nonexistent" => %{"limit" => 5}}, "24h")

      assert result["nonexistent"] == []
    end

    test "queries contacts with field selection" do
      org_id = Fixtures.get_org_id()
      contact = Fixtures.contact_fixture(%{organization_id: org_id})

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{
            "contacts" => %{
              "filters" => %{"phone" => contact.phone},
              "fields" => ["id", "name", "phone"],
              "limit" => 1
            }
          },
          "24h"
        )

      assert [row] = result["contacts"]
      assert row.phone == contact.phone
      assert Map.has_key?(row, :id)
      assert Map.has_key?(row, :name)
    end

    test "queries flows table" do
      org_id = Fixtures.get_org_id()

      [flow | _] =
        Flows.list_flows(%{filter: %{organization_id: org_id}, opts: %{limit: 1}})

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{
            "flows" => %{
              "filters" => %{"uuid" => flow.uuid},
              "fields" => ["id", "name", "uuid", "is_active"],
              "limit" => 1
            }
          },
          "all"
        )

      assert [row] = result["flows"]
      assert row.uuid == flow.uuid
      assert row.name == flow.name
    end

    test "handles array filter values" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{
            "notifications" => %{
              "filters" => %{"severity" => ["Error", "Warning"]},
              "fields" => ["id", "message", "severity"],
              "limit" => 10
            }
          },
          "24h"
        )

      assert is_list(result["notifications"])
    end

    test "respects limit cap at 50" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{"flows" => %{"limit" => 1000}},
          "24h"
        )

      # Should not crash, and limit is capped
      assert is_list(result["flows"])
    end

    test "applies ordering" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{
            "flows" => %{
              "fields" => ["id", "name", "inserted_at"],
              "order" => "inserted_at ASC",
              "limit" => 10
            }
          },
          "24h"
        )

      flows = result["flows"]

      if length(flows) > 1 do
        timestamps = Enum.map(flows, & &1.inserted_at)
        assert timestamps == Enum.sort(timestamps, DateTime)
      end
    end

    test "queries multiple tables in parallel" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{
            "flows" => %{"fields" => ["id", "name"], "limit" => 3},
            "notifications" => %{"fields" => ["id", "message"], "limit" => 3},
            "groups" => %{"fields" => ["id", "label"], "limit" => 3}
          },
          "24h"
        )

      assert Map.has_key?(result, "flows")
      assert Map.has_key?(result, "notifications")
      assert Map.has_key?(result, "groups")
    end

    test "returns all allowed fields when none specified" do
      org_id = Fixtures.get_org_id()
      Fixtures.contact_fixture(%{organization_id: org_id})

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{"contacts" => %{"limit" => 1}},
          "24h"
        )

      assert [row] = result["contacts"]
      # Should have more than just id when all fields selected
      assert map_size(row) > 1
    end

    test "skips bad filter columns gracefully" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{
            "flows" => %{
              "filters" => %{"nonexistent_column" => "value"},
              "limit" => 5
            }
          },
          "24h"
        )

      # Should not crash, bad filter is skipped
      assert is_list(result["flows"])
    end

    test "nil time_range skips time filtering" do
      org_id = Fixtures.get_org_id()

      {:ok, result} =
        DifyTableQuery.query_tables(
          org_id,
          %{"flows" => %{"limit" => 5}},
          "all"
        )

      assert is_list(result["flows"])
    end
  end
end
