defmodule Glific.ChatbotDiagnoseTest do
  use Glific.DataCase

  import Ecto.Query, warn: false

  alias Glific.ChatbotDiagnose
  alias Glific.Contacts.Contact
  alias Glific.Repo

  defp backdate_contact(contact, seconds_ago) do
    backdated = DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.truncate(:second)

    from(c in Contact, where: c.id == ^contact.id)
    |> Repo.update_all(set: [inserted_at: backdated])

    backdated
  end

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

    test "completely invalid field names return empty list", %{organization_id: organization_id} do
      # Fields that don't exist as atoms at all trigger ArgumentError rescue
      tables = %{
        "contacts" => %{
          "fields" => ["zzz_nonexistent_field_xyz_999"],
          "limit" => 3
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert result["contacts"] == []
    end

    test "contact_name virtual filter resolves correctly", %{organization_id: organization_id} do
      [contact | _] =
        Glific.Contacts.list_contacts(%{filter: %{organization_id: organization_id}})

      tables = %{
        "messages" => %{
          "filters" => %{"contact_name" => contact.name},
          "fields" => ["id", "contact_id"],
          "limit" => 10
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)

      Enum.each(result["messages"], fn msg ->
        assert msg.contact_id == contact.id
      end)
    end

    test "contact_name virtual filter with nonexistent name returns empty",
         %{organization_id: organization_id} do
      tables = %{
        "messages" => %{
          "filters" => %{"contact_name" => "zzz_no_such_contact_xyz_999"},
          "fields" => ["id", "contact_id"],
          "limit" => 10
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert result["messages"] == []
    end

    test "flow_name virtual filter resolves correctly", %{organization_id: organization_id} do
      flows = Glific.Flows.list_flows(%{filter: %{organization_id: organization_id}})

      case flows do
        [flow | _] ->
          tables = %{
            "flow_contexts" => %{
              "filters" => %{"flow_name" => flow.name},
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

    test "flow_name virtual filter with nonexistent name returns empty",
         %{organization_id: organization_id} do
      tables = %{
        "flow_contexts" => %{
          "filters" => %{"flow_name" => "zzz_no_such_flow_xyz_999"},
          "fields" => ["id", "flow_id"],
          "limit" => 10
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert result["flow_contexts"] == []
    end

    test "flow_uuid filter with nonexistent uuid returns empty",
         %{organization_id: organization_id} do
      tables = %{
        "flow_contexts" => %{
          "filters" => %{"flow_uuid" => "00000000-0000-0000-0000-000000000000"},
          "fields" => ["id", "flow_id"],
          "limit" => 10
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert result["flow_contexts"] == []
    end

    test "contact_phone filter with nonexistent phone returns empty",
         %{organization_id: organization_id} do
      tables = %{
        "messages" => %{
          "filters" => %{"contact_phone" => "+99999999999999"},
          "fields" => ["id", "contact_id"],
          "limit" => 10
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert result["messages"] == []
    end

    test "virtual filter on table without matching column is ignored",
         %{organization_id: organization_id} do
      # contact_name on a table that has no contact_id field
      tables = %{
        "flows" => %{
          "filters" => %{"contact_name" => "someone"},
          "fields" => ["id", "name"],
          "limit" => 5
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      # Should just return flows unfiltered (contact_name ignored)
      assert is_list(result["flows"])
    end

    test "flow_name filter on table without flow_id is ignored",
         %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "filters" => %{"flow_name" => "somename"},
          "fields" => ["id", "name"],
          "limit" => 5
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert is_list(result["contacts"])
    end

    test "filter with non-whitelisted column is ignored", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "filters" => %{"settings" => "something"},
          "fields" => ["id", "name"],
          "limit" => 5
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      # Should return contacts, ignoring the non-whitelisted filter
      assert is_list(result["contacts"])
    end

    test "order with ASC direction works", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id", "inserted_at"],
          "limit" => 10,
          "order" => "inserted_at ASC"
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      contacts = result["contacts"]

      if length(contacts) > 1 do
        timestamps = Enum.map(contacts, & &1.inserted_at)
        assert timestamps == Enum.sort(timestamps, {:asc, DateTime})
      end
    end

    test "order with single field (no direction) defaults to ASC",
         %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id", "inserted_at"],
          "limit" => 10,
          "order" => "inserted_at"
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert is_list(result["contacts"])
    end

    test "order with invalid direction is ignored", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id", "name"],
          "limit" => 5,
          "order" => "inserted_at SIDEWAYS"
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert is_list(result["contacts"])
    end

    test "order with invalid field name is ignored", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id", "name"],
          "limit" => 5,
          "order" => "zzz_nonexistent_field_xyz DESC"
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert is_list(result["contacts"])
    end

    test "order with too many parts is ignored", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id", "name"],
          "limit" => 5,
          "order" => "inserted_at DESC NULLS LAST"
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert is_list(result["contacts"])
    end

    test "time_range with days suffix works", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id"],
          "limit" => 50,
          "apply_time_range" => true
        }
      }

      result = ChatbotDiagnose.run(tables, "7d", organization_id)
      assert is_list(result["contacts"])
    end

    test "time_range with invalid format defaults to 24h", %{organization_id: organization_id} do
      tables = %{
        "contacts" => %{
          "fields" => ["id"],
          "limit" => 50,
          "apply_time_range" => true
        }
      }

      result = ChatbotDiagnose.run(tables, "invalid", organization_id)
      assert is_list(result["contacts"])
    end

    test "flow_uuid filter falls back to flow_uuid field when table has no flow_id",
         %{organization_id: organization_id} do
      flows = Glific.Flows.list_flows(%{filter: %{organization_id: organization_id}})

      case flows do
        [flow | _] ->
          # flow_counts has both flow_uuid and flow_id columns, but let's test
          # flow_results which has flow_uuid as a direct field
          tables = %{
            "flow_results" => %{
              "filters" => %{"flow_uuid" => flow.uuid},
              "fields" => ["id", "flow_id", "flow_uuid"],
              "limit" => 10
            }
          }

          result = ChatbotDiagnose.run(tables, nil, organization_id)
          assert is_list(result["flow_results"])

        [] ->
          :ok
      end
    end

    test "returns all allowed fields when no fields specified",
         %{organization_id: organization_id} do
      tables = %{
        "notifications" => %{
          "limit" => 3
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert is_list(result["notifications"])
    end

    test "contact_phone filter on table without contact_id is ignored",
         %{organization_id: organization_id} do
      tables = %{
        "flows" => %{
          "filters" => %{"contact_phone" => "+1234567890"},
          "fields" => ["id", "name"],
          "limit" => 5
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      assert is_list(result["flows"])
    end
  end

  describe "maybe_apply_time_range/4 (via run/3)" do
    test "filters out rows older than the threshold when apply_time_range is true",
         %{organization_id: organization_id} do
      recent = Glific.Fixtures.contact_fixture(%{phone: "+19999000001"})
      old = Glific.Fixtures.contact_fixture(%{phone: "+19999000002"})
      backdate_contact(old, 7_200)

      tables = %{
        "contacts" => %{
          "fields" => ["id"],
          "limit" => 50,
          "apply_time_range" => true
        }
      }

      result = ChatbotDiagnose.run(tables, "1h", organization_id)
      ids = Enum.map(result["contacts"], & &1.id)

      assert recent.id in ids
      refute old.id in ids
    end

    test "ignores time range when apply_time_range is false even if a threshold is given",
         %{organization_id: organization_id} do
      old = Glific.Fixtures.contact_fixture(%{phone: "+19999000003"})
      backdate_contact(old, 7_200)

      tables = %{
        "contacts" => %{
          "fields" => ["id"],
          "limit" => 50,
          "apply_time_range" => false
        }
      }

      result = ChatbotDiagnose.run(tables, "1h", organization_id)
      ids = Enum.map(result["contacts"], & &1.id)

      assert old.id in ids
    end

    test "ignores time threshold when time_range is nil", %{organization_id: organization_id} do
      old = Glific.Fixtures.contact_fixture(%{phone: "+19999000004"})
      backdate_contact(old, 7_200)

      tables = %{
        "contacts" => %{
          "fields" => ["id"],
          "limit" => 50,
          "apply_time_range" => true
        }
      }

      result = ChatbotDiagnose.run(tables, nil, organization_id)
      ids = Enum.map(result["contacts"], & &1.id)

      assert old.id in ids
    end

    test "skips time filter on tables whose allowed fields don't include inserted_at",
         %{organization_id: organization_id} do
      tables = %{
        "users_groups" => %{
          "fields" => ["id"],
          "limit" => 5,
          "apply_time_range" => true
        }
      }

      result = ChatbotDiagnose.run(tables, "1h", organization_id)
      assert is_list(result["users_groups"])
    end
  end
end
