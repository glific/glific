defmodule Glific.ReportsTest do
  use Glific.DataCase

  alias Glific.{Fixtures, Reports}

  test "get_date_preset/3" do
    end_day = NaiveDateTime.utc_now() |> Timex.beginning_of_day()

    start_day =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-7, :day)
      |> Timex.beginning_of_day()

    date_range = %{
      end_day: end_day,
      start_day: start_day
    }

    assert %{end_day: _, start_day: _, date_map: _} = Reports.get_date_preset(date_range)
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

  test "get_kpi/3 counts contacts without a phone", %{organization_id: org_id} do
    date_range = %{
      start_day: ~U[2000-01-01 00:00:00Z],
      end_day: DateTime.add(DateTime.utc_now(), 60)
    }

    valid_before = Reports.get_kpi(:valid_contact_count, org_id, date_range)
    non_opted_before = Reports.get_kpi(:non_opted_contacts_count, org_id, date_range)

    Fixtures.contact_without_phone_fixture(%{organization_id: org_id})

    assert valid_before + 1 == Reports.get_kpi(:valid_contact_count, org_id, date_range)
    assert non_opted_before + 1 == Reports.get_kpi(:non_opted_contacts_count, org_id, date_range)
  end
end
