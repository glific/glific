defmodule GlificWeb.Schema.SheetTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Repo,
    Sheets.Sheet
  }

  load_gql(:count, GlificWeb.Schema, "assets/gql/sheets/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/sheets/list.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/sheets/create.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/sheets/by_id.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/sheets/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/sheets/delete.gql")
  load_gql(:sync_sheet, GlificWeb.Schema, "assets/gql/sheets/sync_sheet.gql")

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

  test "count returns the number of sheets", %{staff: user} = attrs do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countSheets"]) == 0
    Fixtures.sheet_fixture(attrs)

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"label" => "sample sheet"}})

    assert get_in(query_data, [:data, "countSheets"]) == 1
  end

  test "sheets field returns list of sheets", %{staff: user} = attrs do
    Fixtures.sheet_fixture(attrs)
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result
    sheets = get_in(query_data, [:data, "sheets"])
    assert length(sheets) > 0
    [sheet | _] = sheets
    assert get_in(sheet, ["label"]) == "sample sheet"
  end

  test "create a sheet and test possible scenarios and errors", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "new sheet",
            "url" =>
              "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createSheet", "sheet", "label"])
    assert label == "new sheet"
    id = get_in(query_data, [:data, "createSheet", "sheet", "id"])

    result = auth_query_gql_by(:sync_sheet, user, variables: %{"id" => id})

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "syncSheet", "sheet", "sheetDataCount"]) == 4
  end

  test "sheet id returns one sheet or nil", %{staff: user} = attrs do
    Fixtures.sheet_fixture(attrs)

    label = "sample sheet"
    {:ok, sheet} = Repo.fetch_by(Sheet, %{label: label, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => sheet.id})
    assert {:ok, query_data} = result

    assert label == get_in(query_data, [:data, "sheet", "sheet", "label"])

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "sheet", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "update a sheet and test possible scenarios and errors", %{manager: user} = attrs do
    Fixtures.sheet_fixture(attrs)
    label = "sample sheet"
    {:ok, sheet} = Repo.fetch_by(Sheet, %{label: label, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => sheet.id,
          "input" => %{"label" => "updated sheet"}
        }
      )

    assert {:ok, query_data} = result
    assert "updated sheet" == get_in(query_data, [:data, "updateSheet", "sheet", "label"])
  end

  test "delete a sheet", %{manager: user} = attrs do
    Fixtures.sheet_fixture(attrs)
    label = "sample sheet"
    {:ok, sheet} = Repo.fetch_by(Sheet, %{label: label, organization_id: user.organization_id})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => sheet.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteSheet", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => sheet.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteSheet", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
