defmodule Glific.ExportTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Partners.Export,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts(organization)
    SeedsDev.seed_messages(organization)
    SeedsDev.hsm_templates(organization)
    SeedsDev.seed_users(organization)
    SeedsDev.seed_interactives(organization)
    :ok
  end

  describe "export" do
    test "export_config/0 returns config info", %{organization_id: _organization_id} do
      config = Export.export_config()

      assert config["languages"] != []
      assert config["languages"] |> length() > 10
      assert config["providers"] != []
      assert config["providers"] |> length() > 10
    end

    test "export_stats/1 returns the stats for a specific organization", %{
      organization_id: organization_id
    } do
      stats = Export.export_stats(organization_id, %{})

      assert map_size(stats) > 0
      assert stats["contacts"] |> length() == 3
      assert stats["contacts"] |> hd() > 0

      assert stats["messages"] |> length() == 3
      assert stats["messages"] |> hd() > 0

      assert stats["organizations"] |> length() == 3
      assert stats["organizations"] |> hd() > 0
    end

    test "export_data/2 returns all the data for a specific organization", %{
      organization_id: organization_id
    } do
      end_time = DateTime.utc_now()
      start_time = DateTime.add(end_time, -7, :day)

      opts = %{
        start_time: start_time,
        end_time: end_time
      }

      export = Export.export_data(organization_id, opts)

      assert export != nil
      assert map_size(export.data) > 0
      assert map_size(export.stats) > 0
    end
  end

  test "export_data/2 returns all the data for a specific organization with table filter", %{
    organization_id: organization_id
  } do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -7, :day)

    opts = %{
      start_time: start_time,
      end_time: end_time,
      tables: ["contacts"]
    }

    export = Export.export_data(organization_id, opts) |> IO.inspect()

    assert export != nil
    assert map_size(export.data) > 0
    assert map_size(export.stats) > 0
  end
end
