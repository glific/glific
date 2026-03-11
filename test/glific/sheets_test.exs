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
    Sheets.Sheet,
    Sheets.SheetData,
    Sheets.Worker
  }

  @fake_service_account Jason.encode!(%{
                          project_id: "test_project",
                          private_key_id: "test_key_id",
                          client_email: "test@test.iam.gserviceaccount.com",
                          private_key: "test_private_key"
                        })

  defp create_google_credentials(organization_id) do
    Partners.create_credential(%{
      shortcode: "google_sheets",
      secrets: %{"service_account" => @fake_service_account},
      is_active: true,
      organization_id: organization_id
    })
  end

  defp mock_sheets_api(values) do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"values" => values})
        }

      %{method: :post} ->
        %Tesla.Env{status: 200, body: "{}"}
    end)
  end

  @default_sheet_values [
    ["Key", "Day", "Message English", "Video link", "Message Hindi"],
    [
      "1/10/2022",
      "1",
      "Hi welcome to Glific. ",
      "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4",
      "Glific में आपका स्वागत है।"
    ],
    [
      "2/10/2022",
      "2",
      "Do you want to explore various programs that we have?",
      "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4",
      "क्या आप हमारे पास मौजूद विभिन्न कार्यक्रमों का पता लगाना चाहते हैं?"
    ],
    ["3/10/2022", "3", "Click on this link to know more about Glific", "", ""],
    ["4/10/2022", "4", "Please share your usecase", "", ""]
  ]

  @sync_sheet_values [
    ["Key", "Value", "Message"],
    ["key1", "val1", "Hello"],
    ["key2", "val2", "World"]
  ]

  describe "sheets" do
    setup_with_mocks([
      {Goth.Token, [],
       [
         fetch: fn _url ->
           {:ok, %{token: "fake_token", expires: System.system_time(:second) + 120}}
         end
       ]}
    ]) do
      :ok
    end

    setup %{organization_id: organization_id} do
      create_google_credentials(organization_id)
      mock_sheets_api(@default_sheet_values)
      :ok
    end

    @valid_attrs %{
      type: "READ",
      label: "sample sheet",
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
      mock_sheets_api([
        ["Key", "Day", "Message English"],
        ["1/10/\u202C2022", "1", "Hi welcome to Glific."],
        ["1/10/2023\u200B", "1", "Hi welcome to Glific 2."],
        ["1/10/2024", "1", "Hi welcome to Glific 3"],
        ["1/10/2026 ", "1", "Hi welcome to Glific 4  "]
      ])

      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Sheet{} = sheet} = Sheets.create_sheet(attrs)
      assert sheet.label == "sample sheet"
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
    setup_with_mocks([
      {Goth.Token, [],
       [
         fetch: fn _url ->
           {:ok, %{token: "fake_token", expires: System.system_time(:second) + 120}}
         end
       ]}
    ]) do
      :ok
    end

    setup %{organization_id: organization_id} do
      create_google_credentials(organization_id)
      mock_sheets_api(@sync_sheet_values)
      :ok
    end

    test "handles successful sync with valid data", %{organization_id: organization_id} do
      attrs = %{
        type: "READ",
        label: "sync test sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)

      assert updated_sheet.sync_status == :success
      assert updated_sheet.sheet_data_count == 2
      assert updated_sheet.last_synced_at != nil
      assert updated_sheet.failure_reason == nil

      sheet_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(sheet_data) == 2

      first_row = Enum.find(sheet_data, fn sd -> sd.key == "key1" end)
      assert first_row.row_data["key"] == "key1"
      assert first_row.row_data["value"] == "val1"
      assert first_row.row_data["message"] == "Hello"
    end

    test "handles write-only sheets without syncing", %{organization_id: organization_id} do
      attrs = %{
        type: "WRITE",
        label: "write only sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      assert {:ok, sheet} = Sheets.sync_sheet_data(sheet)

      # No sheet data should be created
      sheet_data_count =
        SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)

      assert sheet_data_count == 0
    end

    test "handles repeated headers", %{organization_id: organization_id} do
      mock_sheets_api([
        ["Key", "Key", "Value"],
        ["key1", "val1", "Hello"],
        ["key2", "val2", "World"]
      ])

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
      mock_sheets_api([["Key", "", ""], ["key1", "val1", "Hello"], ["key2", "val2", "World"]])

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
      mock_sheets_api([
        ["Key", "Value", "Message"],
        ["key1", "val1", "Hello"],
        ["key1", "val2", "World"]
      ])

      attrs = %{
        type: "READ",
        label: "duplicate keys sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed
      assert updated_sheet.failure_reason == "Key: has already been taken (Value: key1)"

      sheet_data_count =
        SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)

      assert sheet_data_count == 0
    end

    test "handles errors when first column value is blank", %{organization_id: organization_id} do
      # First column value is empty string → key is blank → validation fails
      mock_sheets_api([
        ["Key", "Value", "Message"],
        ["", "val1", "Hello"],
        ["key2", "val2", "World"]
      ])

      attrs = %{
        type: "READ",
        label: "blank key sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed
      assert updated_sheet.failure_reason == "Key: can't be blank"

      sheet_data_count =
        SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)

      assert sheet_data_count == 0
    end

    test "handles Google Sheets API errors gracefully", %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 403, body: "Forbidden"}
      end)

      attrs = %{
        type: "READ",
        label: "api error sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      assert {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)
      assert updated_sheet.sync_status == :failed
      assert updated_sheet.failure_reason =~ "403"
    end

    test "handles empty sheet data", %{organization_id: organization_id} do
      # API returns empty values array → no rows to process → validation fails
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: Jason.encode!(%{"values" => []})
          }
      end)

      attrs = %{
        type: "READ",
        label: "empty sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

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

      {:ok, updated_sheet} = Sheets.sync_sheet_data(sheet)

      sheet_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(sheet_data) == 2

      assert updated_sheet.sync_status == :success

      assert_enqueued(
        worker: Worker,
        prefix: global_schema,
        args: %{sheet_id: sheet.id, organization_id: organization_id},
        tags: ["media_validation"]
      )
    end

    test "cleans up existing sheet data upon successful sync", %{organization_id: organization_id} do
      attrs = %{
        type: "READ",
        label: "cleanup test sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()

      {:ok, _} =
        Sheets.create_sheet_data(%{
          key: "old_key",
          row_data: %{"key" => "old_key", "value" => "old_value"},
          sheet_id: sheet.id,
          organization_id: organization_id,
          last_synced_at: DateTime.utc_now()
        })

      initial_count = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.aggregate(:count)
      assert initial_count == 1

      assert {:ok, _updated_sheet} = Sheets.sync_sheet_data(sheet)

      sheet_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(sheet_data) == 2

      refute Enum.find(sheet_data, fn sd -> sd.key == "old_key" end)

      new_data = Enum.find(sheet_data, fn sd -> sd.key == "key1" end)
      assert new_data != nil
    end

    test "preserves existing sheet data when resync fails", %{organization_id: organization_id} do
      attrs = %{
        type: "READ",
        label: "data preservation test sheet",
        url:
          "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        organization_id: organization_id
      }

      {:ok, sheet} = %Sheet{} |> Sheet.changeset(attrs) |> Repo.insert()
      {:ok, sheet_after_first_sync} = Sheets.sync_sheet_data(sheet)

      initial_data = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(initial_data) == 2

      initial_data_ids = Enum.map(initial_data, fn data -> data.id end)

      # Simulate failing resync via Google API error
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 500, body: "Internal Server Error"}
      end)

      {:ok, sheet_after_failed_sync} = Sheets.sync_sheet_data(sheet_after_first_sync)

      assert sheet_after_failed_sync.sync_status == :failed
      assert sheet_after_failed_sync.failure_reason != nil

      data_after_failed_sync = SheetData |> where([sd], sd.sheet_id == ^sheet.id) |> Repo.all()
      assert length(data_after_failed_sync) == 2

      preserved_data_ids = Enum.map(data_after_failed_sync, fn data -> data.id end)
      assert Enum.sort(initial_data_ids) == Enum.sort(preserved_data_ids)

      assert Enum.any?(data_after_failed_sync, fn data ->
               data.key == "key1" && data.row_data["message"] == "Hello"
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
end
