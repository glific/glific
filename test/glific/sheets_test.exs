defmodule Glific.SheetsTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  import Ecto.Query
  import Mock

  alias Glific.{
    Fixtures,
    Notifications,
    Partners,
    Repo,
    Sheets,
    Sheets.GoogleSheets,
    Sheets.Sheet,
    Sheets.SheetData,
    Sheets.Worker
  }

  describe "sheets" do
    setup do
      Tesla.Mock.mock(fn
        %{method: :get, url: nil} ->
          {:error, :invalid_url}

        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              "Key,Day,Message English,Video link,Message Hindi\r\n1/10/2022,1,Hi welcome to Glific. ,http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4,Glific में आपका स्वागत है।\r\n2/10/2022,2,Do you want to explore various programs that we have?,http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4,क्या आप हमारे पास मौजूद विभिन्न कार्यक्रमों का पता लगाना चाहते हैं?\r\n3/10/2022,3,Click on this link to know more about Glific,,Glific के बारे में अधिक जानने के लिए इस लिंक पर क्लिक करें\r\n4/10/2022,4,Please share your usecase,,कृपया अपना उपयोगकेस साझा करें"
          }
      end)

      :ok
    end

    @valid_attrs %{
      type: "READ",
      label: "sample sheet",
      # this is sample sheet url
      url:
        "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
    }
    @update_attrs %{
      label: "updated sheet"
    }
    @invalid_attrs %{
      label: "invalid sheet",
      url: nil
    }

    test "list_sheets/1 returns all sheets", attrs do
      sheet = Fixtures.sheet_fixture(attrs)

      assert Enum.filter(
               Sheets.list_sheets(%{filter: attrs}),
               fn s -> s.label == sheet.label end
             ) ==
               [sheet]
    end

    test "count_sheets/1 returns count of all sheets", attrs do
      sheet_count = Sheets.count_sheets(%{filter: attrs})

      Fixtures.sheet_fixture(attrs)
      assert Sheets.count_sheets(%{filter: attrs}) == sheet_count + 1
    end

    test "get_sheet!/1 returns the sheet with given id", attrs do
      sheet = Fixtures.sheet_fixture(attrs)
      assert Sheets.get_sheet!(sheet.id) == sheet
    end

    test "create_sheet/1 with valid data creates a sheet", %{organization_id: organization_id} do
      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Sheet{} = sheet} = Sheets.create_sheet(attrs)
      assert sheet.label == "sample sheet"
      assert sheet.url == @valid_attrs.url
      assert sheet.is_active == true
      assert sheet.organization_id == organization_id
    end

    test "create_sheet/1 with invalid data returns error changeset" do
      assert {:error, "Invalid sheet URL"} = Sheets.create_sheet(@invalid_attrs)
    end

    test "update_sheet/2 with valid data updates the sheet", attrs do
      sheet = Fixtures.sheet_fixture(attrs)
      assert {:ok, %Sheet{} = sheet} = Sheets.update_sheet(sheet, @update_attrs)
      assert sheet.is_active == true
      assert sheet.label == "updated sheet"
    end

    test "update_sheet/2 with invalid data returns error changeset", attrs do
      sheet = Fixtures.sheet_fixture(attrs)
      assert {:error, "Invalid sheet URL"} = Sheets.update_sheet(sheet, @invalid_attrs)
      assert sheet == Sheets.get_sheet!(sheet.id)
    end

    test "delete_sheet/1 deletes the sheet", attrs do
      sheet = Fixtures.sheet_fixture(attrs)
      assert {:ok, %Sheet{}} = Sheets.delete_sheet(sheet)
      assert_raise Ecto.NoResultsError, fn -> Sheets.get_sheet!(sheet.id) end
    end

    test "sync_organization_sheets/1 sync all the sheets of organization",
         %{organization_id: organization_id} = attrs do
      Fixtures.sheet_fixture(attrs)
      assert Sheets.sync_organization_sheets(organization_id) == :ok
    end

    test "create_sheet/1 with valid data creates a sheet, where Key has invisible characters", %{
      organization_id: organization_id
    } do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              "Key,Day,Message English\r\n1/10/\u202C2022,1,Hi welcome to Glific.\r\n1/10/2023\u200B,1,Hi welcome to Glific 2.\r\n1/10/2024,1,Hi welcome to Glific 3\r\n1/10/2026 ,1,Hi welcome to Glific 4  "
          }
      end)

      valid_attrs = %{
        type: "READ",
        label: "sample sheet",
        # this is sample sheet url
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
      }

      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Sheet{} = sheet} = Sheets.create_sheet(attrs)
      assert sheet.label == "sample sheet"
      assert sheet.url == valid_attrs.url
      assert sheet.is_active == true
      assert sheet.organization_id == organization_id

      [h | [t | [t1 | [t2 | _]]]] =
        SheetData
        |> where([sd], sd.sheet_id == ^sheet.id)
        |> Repo.all([])

      assert h.row_data["key"] == "1/10/2022"
      assert t.row_data["key"] == "1/10/2023"
      assert t1.row_data["key"] == "1/10/2024"
      assert t2.row_data["key"] == "1/10/2026"
      assert t2.row_data["message_english"] == "Hi welcome to Glific 4"
    end
  end

  describe "sync_sheet_data/1" do
    setup do
      # Default success mock for CSV content
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Key,Value,Message\r\nkey1,val1,Hello\r\nkey2,val2,World"
          }
      end)

      :ok
    end

    test "handles successful sync with valid data", %{organization_id: organization_id} do
      # Create a sheet to sync
      attrs = %{
        type: "READ",
        label: "sync test sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Sync the sheet
      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)

      # Check sheet was updated correctly
      assert updated_sheet.sync_status == :success
      assert updated_sheet.sheet_data_count == 2
      assert updated_sheet.last_synced_at != nil
      assert updated_sheet.failure_reason == nil

      # Check sheet data was created correctly
      sheet_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(sheet_data) == 2

      # Check specific row data
      first_row = Enum.find(sheet_data, fn sd -> sd.key == "key1" end)
      assert first_row.row_data["key"] == "key1"
      assert first_row.row_data["value"] == "val1"
      assert first_row.row_data["message"] == "Hello"
    end

    test "handles write-only sheets without syncing", %{organization_id: organization_id} do
      # Create a WRITE type sheet
      attrs = %{
        type: "WRITE",
        label: "write only sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # WRITE sheets should return immediately without syncing
      assert {:ok, sheet} = Sheets.sync_sheet_data(sheet)

      # No sheet data should be created
      sheet_data_count =
        SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)

      assert sheet_data_count == 0
    end

    test "handles repeated headers", %{organization_id: organization_id} do
      # Mock a CSV with invalid headers (repeated headers)
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Key,Key,Value\r\nkey1,val1,Hello\r\nkey2,val2,World"
          }
      end)

      attrs = %{
        type: "READ",
        label: "invalid headers sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Sync should fail due to invalid headers
      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed

      assert updated_sheet.failure_reason == "Repeated or missing headers"

      # No sheet data should be created
      sheet_data_count =
        SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)

      assert sheet_data_count == 0
    end

    test "handles missing headers", %{organization_id: organization_id} do
      # Mock a CSV with invalid headers (missing headers)
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Key,,\r\nkey1,val1,Hello\r\nkey2,val2,World"
          }
      end)

      attrs = %{
        type: "READ",
        label: "invalid headers sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Sync should fail due to missing headers
      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed

      assert updated_sheet.failure_reason == "Repeated or missing headers"

      # No sheet data should be created
      sheet_data_count =
        SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)

      assert sheet_data_count == 0
    end

    test "handles duplicate key errors", %{organization_id: organization_id} do
      # Mock a CSV with duplicate keys
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Key,Value,Message\r\nkey1,val1,Hello\r\nkey1,val2,World"
          }
      end)

      attrs = %{
        type: "READ",
        label: "duplicate keys sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Sync should fail due to duplicate keys
      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed

      assert updated_sheet.failure_reason == "Key: has already been taken (Value: key1)"

      # No sheet data should be created
      sheet_data_count =
        SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)

      assert sheet_data_count == 0
    end

    test "handles errors when key is missing", %{organization_id: organization_id} do
      # Mock a CSV with missing "key" column
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Value,Message\r\nval1,Hello\r\nval2,World"
          }
      end)

      attrs = %{
        type: "READ",
        label: "keys missing sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Sync should fail due to missing "key" column
      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed

      assert updated_sheet.failure_reason == "Key: can't be blank"

      # No sheet data should be created
      sheet_data_count =
        SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)

      assert sheet_data_count == 0
    end

    test "handles CSV parsing errors", %{organization_id: organization_id} do
      # Mock a CSV with parsing error
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Key,Value,Message\r\n\"unclosed quote,val1,Hello\r\nkey2,val2,World"
          }
      end)

      attrs = %{
        type: "READ",
        label: "parse error sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Should handle the CSV parsing error gracefully
      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed
      assert updated_sheet.failure_reason =~ "Escape sequence started on line 2:\\n\\n\\"
    end

    test "handles HTTP errors when fetching CSV", %{organization_id: organization_id} do
      # Mock an HTTP failure
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 500,
            body: "Internal Server Error"
          }
      end)

      attrs = %{
        type: "READ",
        label: "http error sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Should handle the HTTP error gracefully
      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed

      assert updated_sheet.failure_reason == "Unknown error or empty content"
    end

    test "schedules a media validation job after syncing a sheet", %{
      organization_id: organization_id,
      global_schema: global_schema
    } do
      attrs = %{
        type: "READ",
        label: "media validation sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Run sync and check results
      {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)

      # We can verify the sheet data was created correctly
      sheet_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(sheet_data) == 2

      # The sync should complete, though there should be warnings
      assert updated_sheet.sync_status == :success

      assert_enqueued(
        worker: Worker,
        prefix: global_schema,
        args: %{sheet_id: sheet.id, organization_id: organization_id},
        tags: ["media_validation"]
      )
    end

    test "cleans up existing sheet data upon successful sync", %{organization_id: organization_id} do
      # Create a sheet
      attrs = %{
        type: "READ",
        label: "cleanup test sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      # Create some initial sheet data
      {:ok, _} =
        Sheets.create_sheet_data(%{
          key: "old_key",
          row_data: %{"key" => "old_key", "value" => "old_value"},
          sheet_id: sheet.id,
          organization_id: organization_id,
          last_synced_at: DateTime.utc_now()
        })

      # Verify initial data exists
      initial_count = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)
      assert initial_count == 1

      # Sync sheet
      assert {:ok, _updated_sheet} = Sheets.sync_sheet_data(sheet)

      # Check that old data was deleted and new data was created
      sheet_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(sheet_data) == 2

      # Verify old data is gone
      refute Enum.find(sheet_data, fn sd -> sd.key == "old_key" end)

      # Verify new data exists
      new_data = Enum.find(sheet_data, fn sd -> sd.key == "key1" end)
      assert new_data != nil
    end

    test "preserves existing sheet data when resync fails", %{organization_id: organization_id} do
      # First create a sheet with valid data
      attrs = %{
        type: "READ",
        label: "data preservation test sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      # Setup initial successful sync
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Key,Value,Message\r\nkey1,val1,Initial data\r\nkey2,val2,Should be preserved"
          }
      end)

      # Create and sync the sheet for the first time
      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()
      {:ok, sheet_after_first_sync} = Sheets.sync_sheet_data(sheet)

      # Verify initial data exists
      initial_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(initial_data) == 2

      # Store the IDs of the initial data
      initial_data_ids = Enum.map(initial_data, fn data -> data.id end)

      # Now mock a failing sync
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            # This invalid format will cause the sync to fail
            body: "Invalid CSV format that will cause a failure"
          }
      end)

      # Attempt to resync which should fail
      {:ok, sheet_after_failed_sync} = Sheets.sync_sheet_data(sheet_after_first_sync)

      # Verify the sync failed
      assert sheet_after_failed_sync.sync_status == :failed
      assert sheet_after_failed_sync.failure_reason != nil

      # Check that the original data is still there
      data_after_failed_sync = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()

      # The data should be preserved - same count as before
      assert length(data_after_failed_sync) == 2

      # Verify it's the same data as before by checking IDs
      preserved_data_ids = Enum.map(data_after_failed_sync, fn data -> data.id end)
      assert Enum.sort(initial_data_ids) == Enum.sort(preserved_data_ids)

      # Double check the content is also preserved
      assert Enum.any?(data_after_failed_sync, fn data ->
               data.key == "key1" && data.row_data["message"] == "Initial data"
             end)
    end
  end

  describe "execute/2 WRITE action error handling" do
    test "creates a notification with the API error message when Google Sheets returns 403",
         %{organization_id: organization_id} do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        Partners.create_credential(%{
          shortcode: "google_sheets",
          secrets: %{
            "service_account" =>
              Jason.encode!(%{
                project_id: "DEFAULT PROJECT ID",
                private_key_id: "DEFAULT API KEY",
                client_email: "DEFAULT CLIENT EMAIL",
                private_key: "DEFAULT PRIVATE KEY"
              })
          },
          is_active: true,
          organization_id: organization_id
        })

        Tesla.Mock.mock(fn
          %{method: :post} ->
            %Tesla.Env{
              status: 403,
              body:
                "{\n  \"error\": {\n    \"code\": 403,\n    \"message\": \"The caller does not have permission\",\n    \"status\": \"PERMISSION_DENIED\"\n  }\n}\n"
            }
        end)

        action = %{
          action_type: "WRITE",
          url:
            "https://docs.google.com/spreadsheets/d/1ZYiMW1PunIT6euVhkxQRXeebFzszGFecGzfzpAoVlFg/edit#gid=0",
          range: "Sheet1!A:A",
          row_data: ["Test data"]
        }

        context = %{
          organization_id: organization_id,
          contact_id: 1,
          flow_id: 1,
          results: %{},
          flow: %{id: 1, uuid: "test-uuid", name: "Test Flow"}
        }

        {_ctx, result} = Sheets.execute(action, context)
        assert result.body == "Failure"

        notification =
          Notifications.list_notifications(%{filter: %{organization_id: organization_id}})
          |> Enum.find(&(&1.category == "Flow"))

        assert notification.message == "The caller does not have permission"
      end
    end

    test "creates a notification with a generic 5xx error message when Google Sheets returns 500 without body",
         %{organization_id: organization_id} do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        Partners.create_credential(%{
          shortcode: "google_sheets",
          secrets: %{
            "service_account" =>
              Jason.encode!(%{
                project_id: "DEFAULT PROJECT ID",
                private_key_id: "DEFAULT API KEY",
                client_email: "DEFAULT CLIENT EMAIL",
                private_key: "DEFAULT PRIVATE KEY"
              })
          },
          is_active: true,
          organization_id: organization_id
        })

        Tesla.Mock.mock(fn
          %{method: :post} ->
            %Tesla.Env{
              status: 500
            }
        end)

        action = %{
          action_type: "WRITE",
          url:
            "https://docs.google.com/spreadsheets/d/1ZYiMW1PunIT6euVhkxQRXeebFzszGFecGzfzpAoVlFg/edit#gid=0",
          range: "Sheet1!A:A",
          row_data: ["Test data"]
        }

        context = %{
          organization_id: organization_id,
          contact_id: 1,
          flow_id: 1,
          results: %{},
          flow: %{id: 1, uuid: "test-uuid", name: "Test Flow"}
        }

        {_ctx, result} = Sheets.execute(action, context)
        assert result.body == "Failure"

        notification =
          Notifications.list_notifications(%{filter: %{organization_id: organization_id}})
          |> Enum.find(&(&1.category == "Flow"))

        assert notification.message ==
                 "Failed to write to the spreadsheet, please retry after some time"
      end
    end

    defmodule RandomWriteError do
      defstruct [:reason]
    end

    test "creates a notification with a generic unknown error message when Google Sheets returns a non-Tesla.Env error",
         %{organization_id: organization_id} do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        Partners.create_credential(%{
          shortcode: "google_sheets",
          secrets: %{
            "service_account" =>
              Jason.encode!(%{
                project_id: "DEFAULT PROJECT ID",
                private_key_id: "DEFAULT API KEY",
                client_email: "DEFAULT CLIENT EMAIL",
                private_key: "DEFAULT PRIVATE KEY"
              })
          },
          is_active: true,
          organization_id: organization_id
        })

        random_error = %RandomWriteError{reason: "some random failure"}

        Tesla.Mock.mock(fn
          %{method: :post} ->
            {:error, random_error}
        end)

        action = %{
          action_type: "WRITE",
          url:
            "https://docs.google.com/spreadsheets/d/1ZYiMW1PunIT6euVhkxQRXeebFzszGFecGzfzpAoVlFg/edit#gid=0",
          range: "Sheet1!A:A",
          row_data: ["Test data"]
        }

        context = %{
          organization_id: organization_id,
          contact_id: 1,
          flow_id: 1,
          results: %{},
          flow: %{id: 1, uuid: "test-uuid", name: "Test Flow"}
        }

        {_ctx, result} = Sheets.execute(action, context)
        assert result.body == "Failure"

        notification =
          Notifications.list_notifications(%{filter: %{organization_id: organization_id}})
          |> Enum.find(&(&1.category == "Flow"))

        assert notification.message ==
                 "Unknown error occurred, please reach out to support"
      end
    end
  end

  @spreadsheet_id "1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw"
  @sheet_url "https://docs.google.com/spreadsheets/d/#{@spreadsheet_id}/edit#gid=0"
  @export_url "https://docs.google.com/spreadsheets/d/#{@spreadsheet_id}/export?format=csv&gid=0"
  @sheets_base_url "https://sheets.googleapis.com/v4/spreadsheets/#{@spreadsheet_id}"

  @service_account_json Jason.encode!(%{
                          project_id: "DEFAULT PROJECT ID",
                          private_key_id: "DEFAULT API KEY",
                          client_email: "DEFAULT CLIENT EMAIL",
                          private_key: "DEFAULT PRIVATE KEY"
                        })

  defp setup_google_sheets_credential(organization_id) do
    Partners.create_credential(%{
      shortcode: "google_sheets",
      secrets: %{"service_account" => @service_account_json},
      is_active: true,
      organization_id: organization_id
    })
  end

  defp spreadsheet_metadata_response do
    Jason.encode!(%{
      spreadsheetId: @spreadsheet_id,
      sheets: [
        %{
          properties: %{
            sheetId: 0,
            title: "Sheet1",
            index: 0
          }
        }
      ]
    })
  end

  defp values_response(rows) do
    Jason.encode!(%{
      range: "'Sheet1'!A1:ZZ1000",
      majorDimension: "ROWS",
      values: rows
    })
  end

  describe "GoogleSheets.read_sheet_data/2 authenticated API path" do
    test "returns rows from Google Sheets API when credentials are available", %{
      organization_id: organization_id
    } do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        setup_google_sheets_credential(organization_id)

        Tesla.Mock.mock(fn
          %{method: :get, url: @sheets_base_url} ->
            %Tesla.Env{status: 200, body: spreadsheet_metadata_response()}

          %{method: :get, url: url} when is_binary(url) ->
            if String.starts_with?(url, @sheets_base_url <> "/values/") do
              %Tesla.Env{
                status: 200,
                body: values_response([["name", "age"], ["Alice", "30"], ["Bob", "25"]])
              }
            end
        end)

        assert {:ok, rows} = GoogleSheets.read_sheet_data(organization_id, @sheet_url)
        assert length(rows) == 2
        assert {:ok, %{"name" => "Alice", "age" => "30"}} = Enum.at(rows, 0)
        assert {:ok, %{"name" => "Bob", "age" => "25"}} = Enum.at(rows, 1)
      end
    end

    test "falls back to public CSV when Google API is not active", %{
      organization_id: organization_id
    } do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "name,age\r\nAlice,30\r\nBob,25"}
      end)

      assert {:ok, rows} = GoogleSheets.read_sheet_data(organization_id, @export_url)
      assert length(rows) == 2
      assert {:ok, %{"name" => "Alice", "age" => "30"}} = Enum.at(rows, 0)
    end

    test "returns empty list when sheet has no data", %{organization_id: organization_id} do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        setup_google_sheets_credential(organization_id)

        Tesla.Mock.mock(fn
          %{method: :get, url: @sheets_base_url} ->
            %Tesla.Env{status: 200, body: spreadsheet_metadata_response()}

          %{method: :get, url: url} when is_binary(url) ->
            if String.starts_with?(url, @sheets_base_url <> "/values/") do
              %Tesla.Env{
                status: 200,
                body: Jason.encode!(%{range: "'Sheet1'!A1:ZZ1", majorDimension: "ROWS"})
              }
            end
        end)

        assert {:ok, []} = GoogleSheets.read_sheet_data(organization_id, @sheet_url)
      end
    end

    test "returns error when API call fails (non-credential error)", %{
      organization_id: organization_id
    } do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        setup_google_sheets_credential(organization_id)

        Tesla.Mock.mock(fn
          %{method: :get, url: @sheets_base_url} ->
            %Tesla.Env{
              status: 403,
              body:
                Jason.encode!(%{
                  error: %{code: 403, message: "The caller does not have permission"}
                })
            }
        end)

        assert {:error, _reason} = GoogleSheets.read_sheet_data(organization_id, @sheet_url)
      end
    end

    test "returns error when gid does not match any sheet", %{organization_id: organization_id} do
      sheet_url_unknown_gid =
        "https://docs.google.com/spreadsheets/d/#{@spreadsheet_id}/edit#gid=9999"

      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        setup_google_sheets_credential(organization_id)

        Tesla.Mock.mock(fn
          %{method: :get, url: @sheets_base_url} ->
            %Tesla.Env{status: 200, body: spreadsheet_metadata_response()}
        end)

        assert {:error, "Sheet with gid 9999 not found"} =
                 GoogleSheets.read_sheet_data(organization_id, sheet_url_unknown_gid)
      end
    end
  end

  describe "GoogleSheets.convert_rows_to_csv_format/1" do
    test "returns empty list for empty input" do
      assert {:ok, []} = GoogleSheets.convert_rows_to_csv_format([])
    end

    test "maps rows to header keys correctly" do
      rows = [["key", "age"], ["1", "22"], ["2", "30"]]

      assert {:ok, results} = GoogleSheets.convert_rows_to_csv_format(rows)
      assert {:ok, %{"key" => "1", "age" => "22"}} = Enum.at(results, 0)
      assert {:ok, %{"key" => "2", "age" => "30"}} = Enum.at(results, 1)
    end

    test "pads short rows with empty strings when row has fewer columns than headers" do
      # row has 2 values but headers have 4 — missing columns should be ""
      rows = [["key", "age", "city", "country"], ["1", "22"]]

      assert {:ok, [{:ok, row_map}]} = GoogleSheets.convert_rows_to_csv_format(rows)
      assert row_map["key"] == "1"
      assert row_map["age"] == "22"
      assert row_map["city"] == ""
      assert row_map["country"] == ""
    end

    test "trims whitespace from headers and row values" do
      rows = [["  key  ", " age "], ["  1  ", "  22  "]]

      assert {:ok, [{:ok, row_map}]} = GoogleSheets.convert_rows_to_csv_format(rows)
      assert row_map["key"] == "1"
      assert row_map["age"] == "22"
    end

    test "returns error for empty header" do
      rows = [["key", "", "city"], ["1", "2", "3"]]

      assert {:error, "Repeated or missing headers"} =
               GoogleSheets.convert_rows_to_csv_format(rows)
    end

    test "returns error for duplicate headers" do
      rows = [["key", "key", "city"], ["1", "2", "3"]]

      assert {:error, "Repeated or missing headers"} =
               GoogleSheets.convert_rows_to_csv_format(rows)
    end

    test "handles row with only headers and no data rows" do
      assert {:ok, []} = GoogleSheets.convert_rows_to_csv_format([["key", "age"]])
    end
  end

  describe "GoogleSheets.get_headers/2" do
    test "returns headers from first row via Google Sheets API", %{
      organization_id: organization_id
    } do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        setup_google_sheets_credential(organization_id)

        Tesla.Mock.mock(fn
          %{method: :get, url: url} when is_binary(url) ->
            if String.contains?(url, "/values/1%3A1") or String.contains?(url, "/values/1:1") do
              %Tesla.Env{
                status: 200,
                body:
                  Jason.encode!(%{
                    range: "Sheet1!A1:ZZ1",
                    majorDimension: "ROWS",
                    values: [["name", "age", "city"]]
                  })
              }
            end
        end)

        assert {:ok, ["name", "age", "city"]} =
                 GoogleSheets.get_headers(organization_id, @spreadsheet_id)
      end
    end

    test "returns error when Google API is not active", %{organization_id: organization_id} do
      assert {:error, "Google API is not active"} =
               GoogleSheets.get_headers(organization_id, @spreadsheet_id)
    end
  end
end
