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
    @invalid_attrs %{
      participants: nil,
      organization_name: nil,
      staff: nil,
      content: nil,
      duration: nil
    }
  end

  test "count_consulting_hours/1 returns count of all consulting_hours",
       %{organization_id: organization_id} = attrs do
    _consulting_hour = Fixtures.consulting_hour_fixture(%{organization_id: organization_id})

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

  test "list_consulting_hours/1 returns all consulting_hours",
       %{organization_id: organization_id} = attrs do
    consulting_hour = Fixtures.consulting_hour_fixture(%{organization_id: organization_id})

    assert Enum.filter(
             ConsultingHour.list_consulting_hours(%{filter: attrs}),
             fn t -> t.staff == consulting_hour.staff end
           ) ==
             [consulting_hour]
  end

  test "create_consulting_hour/1 with valid data creates a consulting_hour", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id, when: DateTime.utc_now()})

    assert {:ok, %ConsultingHour{} = consulting_hour} =
             ConsultingHour.create_consulting_hour(attrs)

    assert consulting_hour.content == "GCS issue"
    assert consulting_hour.is_billable == true
    assert consulting_hour.participants == "Adam"
    assert consulting_hour.staff == "Adelle Cavin"
    assert consulting_hour.organization_id == organization_id
  end

  test "create_consulting_hour/1 with invalid data returns error changeset", %{organization_id: organization_id} do
    attrs =
      Map.merge(@invalid_attrs, %{organization_id: organization_id, when: DateTime.utc_now()})

    assert {:error, %Ecto.Changeset{}} = ConsultingHour.create_consulting_hour(attrs)
  end
end
