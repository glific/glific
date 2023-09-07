defmodule Glific.ReportsTest do
  use Glific.DataCase

  alias Glific.Reports

  test "get_date_preset/3" do
    assert %{today: _, last_day: _, date_map: _} = Reports.get_date_preset()
  end

  test "shifted_time/2 Shift time by no. of days" do
    assert %NaiveDateTime{} = Reports.shifted_time(NaiveDateTime.utc_now(), 2)
  end

  test "get_bookmark_data/1 get all the bookmarks", %{organization_id: org_id} = _attrs do
    # without any bookmarks
    assert Reports.get_bookmark_data(org_id) == %{}

    Reports.save_bookmark_data(%{"name" => "example", "link" => "https://example.com"}, org_id)
    # after adding bookmark
    assert Reports.get_bookmark_data(org_id) == %{"example" => "https://example.com"}

    Reports.delete_bookmark_data(%{"name" => "example"}, org_id)
    # after removing bookmark
    assert Reports.get_bookmark_data(org_id) == %{}
  end
end
