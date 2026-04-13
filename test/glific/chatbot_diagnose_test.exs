defmodule Glific.ChatbotDiagnoseTest do
  use Glific.DataCase

  alias Glific.ChatbotDiagnose

  describe "run/3" do
    test "returns empty results for unknown tables", %{organization_id: organization_id} do
      tables = %{
        "unknown_table" => %{
          "fields" => ["id"],
          "limit" => 5
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      assert result["unknown_table"] == []
    end

    test "queries a known table successfully", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id", "name", "phone"],
          "limit" => 5
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      assert is_list(result["contacts"])

      Enum.each(result["contacts"], fn contact ->
        assert Map.has_key?(contact, :id)
        assert Map.has_key?(contact, :name)
        assert Map.has_key?(contact, :phone)
        # Should not include fields not requested
        refute Map.has_key?(contact, :status)
      end)
    end

    test "respects limit cap at 50", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id"],
          "limit" => 200
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      # Should have at most 50 results even though 200 was requested
      assert length(result["contacts"]) <= 50
    end

    test "applies time range only when apply_time_range is true",
         %{organization_id: organization_id} do
      # With apply_time_range: true and a narrow window
      tables_with_time = %{
        "contacts" => %{
          "fields" => ["id", "inserted_at"],
          "limit" => 50,
          "apply_time_range" => true
        }
      }

      # Without apply_time_range (should return all regardless of time_range)
      tables_without_time = %{
        "contacts" => %{
          "fields" => ["id", "inserted_at"],
          "limit" => 50
        }
      }

      result_with = ChatbotDiagnose.run(tables_with_time, "1h", organization_id)
      result_without = ChatbotDiagnose.run(tables_without_time, "1h", organization_id)

      # Without apply_time_range flag, time_range is ignored → more or equal results
      assert length(result_with["contacts"]) <= length(result_without["contacts"])
    end

    test "no time filter when time_range is nil", %{organization_id: organization_id} do
      # Even with apply_time_range: true, nil time_range means no filtering
      tables = %{
        "contacts" => %{
          "fields" => ["id"],
          "limit" => 50,
          "apply_time_range" => true
        }
      }

      result_nil = ChatbotDiagnose.run(tables, nil, organization_id)

      result_no_flag =
        ChatbotDiagnose.run(
          %{
            "contacts" => %{"fields" => ["id"], "limit" => 50}
          },
          nil,
          organization_id
        )

      # Both should return the same results since time_range is nil
      assert length(result_nil["contacts"]) == length(result_no_flag["contacts"])
    end

    test "filters by string value", %{organization_id: organization_id} do
      [contact | _] =
        Glific.Contacts.list_contacts(%{filter: %{organization_id: organization_id}})

      tables = %{
        "contacts" => %{
          "filters" => %{"phone" => contact.phone},
          "fields" => ["id", "phone"],
          "limit" => 5
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      assert length(result["contacts"]) >= 1

      Enum.each(result["contacts"], fn c ->
        assert c.phone == contact.phone
      end)
    end

    test "filters by null value", %{organization_id: organization_id} do
      tables = %{
        "flow_contexts" => %{
          "filters" => %{"completed_at" => nil},
          "fields" => ["id", "completed_at"],
          "limit" => 10
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      Enum.each(result["flow_contexts"], fn ctx ->
        assert is_nil(ctx.completed_at)
      end)
    end

    test "resolves flow_uuid virtual filter", %{organization_id: organization_id} do
      flows = Glific.Flows.list_flows(%{filter: %{organization_id: organization_id}})

      case flows do
        [flow | _] ->
          tables = %{
            "flow_contexts" => %{
              "filters" => %{"flow_uuid" => flow.uuid},
              "fields" => ["id", "flow_id"],
              "limit" => 10
            }
          }

          result = ChatbotDiagnose.run(tables, nil, organization_id)

          Enum.each(result["flow_contexts"], fn ctx ->
            assert ctx.flow_id == flow.id
          end)

        [] ->
          :ok
      end
    end

    test "resolves contact_phone virtual filter", %{organization_id: organization_id} do
      [contact | _] =
        Glific.Contacts.list_contacts(%{filter: %{organization_id: organization_id}})

      tables = %{
        "messages" => %{
          "filters" => %{"contact_phone" => contact.phone},
          "fields" => ["id", "contact_id"],
          "limit" => 10
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      Enum.each(result["messages"], fn msg ->
        assert msg.contact_id == contact.id
      end)
    end

    test "handles multiple tables in one request", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{"fields" => ["id", "name"], "limit" => 3},
        "flows" => %{"fields" => ["id", "name", "uuid"], "limit" => 3},
        "notifications" => %{"fields" => ["id", "message"], "limit" => 3}
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      assert Map.has_key?(result, "contacts")
      assert Map.has_key?(result, "flows")
      assert Map.has_key?(result, "notifications")
    end

    test "only returns whitelisted fields", %{organization_id: organization_id} do
      tables = %{
        "flow_revisions" => %{
          "fields" => ["id", "revision_number", "definition", "status"],
          "limit" => 3
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      # definition is excluded from the whitelist
      Enum.each(result["flow_revisions"], fn rev ->
        refute Map.has_key?(rev, :definition)
        assert Map.has_key?(rev, :id)
      end)
    end

    test "order parameter works", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id", "inserted_at"],
          "limit" => 10,
          "order" => "inserted_at DESC"
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      contacts = result["contacts"]

      if length(contacts) > 1 do
        timestamps = Enum.map(contacts, & &1.inserted_at)

        assert timestamps ==
                 Enum.sort(timestamps, {:desc, DateTime})
      end
    end

    test "disallowed fields are filtered out silently", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id", "name", "settings", "fields"],
          "limit" => 3
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      # settings and fields are NOT in the whitelist for contacts
      Enum.each(result["contacts"], fn c ->
        refute Map.has_key?(c, :settings)
        refute Map.has_key?(c, :fields)
      end)
    end
  end
end
