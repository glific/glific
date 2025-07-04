defmodule Glific.SheetsTest do
  import Ecto.Query

  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Repo,
    Sheets,
    Sheets.Sheet,
    Sheets.SheetData
  }

  describe "sheets" do
    setup do
      Tesla.Mock.mock(fn
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
      assert {:error, %Ecto.Changeset{}} = Sheets.create_sheet(@invalid_attrs)
    end

    test "update_sheet/2 with valid data updates the sheet", attrs do
      sheet = Fixtures.sheet_fixture(attrs)
      assert {:ok, %Sheet{} = sheet} = Sheets.update_sheet(sheet, @update_attrs)
      assert sheet.is_active == true
      assert sheet.label == "updated sheet"
    end

    test "update_sheet/2 with invalid data returns error changeset", attrs do
      sheet = Fixtures.sheet_fixture(attrs)
      assert {:error, %Ecto.Changeset{}} = Sheets.update_sheet(sheet, @invalid_attrs)
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

    test "create_sheet/1, Handling case where some column having no headers", %{
      organization_id: organization_id
    } do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Key,Val,,\r\napple,3,3,4"
          }
      end)

      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Sheet{} = sheet} = Sheets.create_sheet(attrs)

      [h | _] =
        SheetData
        |> where([sd], sd.sheet_id == ^sheet.id)
        |> Repo.all([])

      assert h.row_data["key"] == "apple"
      assert h.row_data["val"] == "3"
      assert h.row_data[""] == ["3", "4"]
    end

    test "create_sheet/1, Handling case where multiple headers having same name", %{
      organization_id: organization_id
    } do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "Key,Val,same,samed,same\r\napple,3,3,4,2"
          }
      end)

      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Sheet{} = sheet} = Sheets.create_sheet(attrs)

      [h | _] =
        SheetData
        |> where([sd], sd.sheet_id == ^sheet.id)
        |> Repo.all([])

      assert h.row_data["key"] == "apple"
      assert h.row_data["val"] == "3"
      assert h.row_data["same"] == ["3", "2"]
    end
  end
end
