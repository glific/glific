defmodule Glific.SheetsTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  import Ecto.Query

  alias Glific.{
    Fixtures,
    Repo,
    Sheets,
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

      assert updated_sheet.failure_reason ==
               "Failed to insert all rows likely due to duplicate keys: expected 2, got 1"

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
end
