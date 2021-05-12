defmodule Glific.ConsultingHourTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Saas.ConsultingHour
  }

  describe "consulting_hours" do
    @valid_attrs %{
      participants: "Adam",
      organization_name: "Glific",
      staff: "Adelle Cavin",
      content: "GCS issue",
      duration: 15
    }
    @valid_more_attrs %{
      participants: "Mark White",
      organization_name: "Glific",
      staff: "Chrissy Cron",
      content: "BigQuery issue",
      duration: 15,
      when: DateTime.utc_now()
    }
    # @update_attrs %{
    #   staff: "Chrissy Cron",
    #   duration: 30
    # }
    # @invalid_attrs %{
    #   participants: nil,
    #   organization_name: nil,
    #   staff: nil,
    #   content: nil,
    #   duration: nil
    # }
  end

  test "count_consulting_hours/1 returns count of all consulting_hours", attrs do
    _consulting_hour = Fixtures.consulting_hour_fixture(Map.merge(attrs, @valid_attrs))

    consulting_hour_count = ConsultingHour.count_consulting_hours(%{filter: attrs})

    _consulting_hour_2 = Fixtures.consulting_hour_fixture(Map.merge(attrs, @valid_attrs))

    assert ConsultingHour.count_consulting_hours(%{filter: attrs}) == consulting_hour_count + 1

    _consulting_hour_3 = Fixtures.consulting_hour_fixture(Map.merge(attrs, @valid_more_attrs))

    # _ = tag_fixture(Map.merge(attrs, @valid_more_attrs))
    assert ConsultingHour.count_consulting_hours(%{filter: attrs}) == consulting_hour_count + 2

    assert ConsultingHour.count_consulting_hours(%{
             filter: Map.merge(attrs, %{staff: "Chrissy Cron"})
           }) == 1
  end
end
