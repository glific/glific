defmodule Glific.SheetsTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Sheets
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

    # @valid_attrs %{
    #   label: "some label",
    #   url: "somelabel"
    # }
    # @valid_more_attrs %{
    #   label: "some label",
    #   url: "somelabel"
    # }
    # @update_attrs %{
    #   label: "some label",
    #   url: "somelabel",
    #   is_active: false
    # }
    # @invalid_attrs %{
    #   label: "some label",
    #   url: "somelabel"
    # }

    test "list_sheets/1 returns all sheets", attrs do
      sheet = Fixtures.sheet_fixture(attrs)

      assert Enum.filter(
               Sheets.list_sheets(%{filter: attrs}),
               fn s -> s.label == sheet.label end
             ) ==
               [sheet]
    end
  end
end
