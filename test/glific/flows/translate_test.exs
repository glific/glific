defmodule Glific.Flows.TranslateTest do
  use Glific.DataCase

  alias Glific.{
    Flows,
    Flows.Translate.Export,
    Flows.Translate.Import,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts()
    SeedsDev.seed_interactives(organization)
    SeedsDev.seed_test_flows(organization)
    :ok
  end

  @help_flow_id 1

  test "ensure that export extracts the right nodes from the help flow", attrs do
    result =
      attrs.organization_id
      |> Flows.get_complete_flow(@help_flow_id)
      |> Export.export_localization()

    [_h1 | [_h2 | rows]] = result

    # check that each row is a 4 element list and is a translation or not
    Enum.each(
      rows,
      fn row ->
        assert length(row) == 4
        [type, uuid, src, dst] = row
        assert type == "action"
        assert String.length(uuid) == 36

        if uuid != "e319cd39-f764-4680-9199-4cb7da647166",
          do: assert(dst == "Hindi #{src} English")
      end
    )
  end

  test "ensure that impport updates the localization structure", attrs do
    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)
    assert map_size(flow.definition["localization"]) == 1
    assert map_size(flow.definition["localization"]["hi"]) == 1
    csv = Export.export_localization(flow)

    Import.import_localization(csv, flow)

    # get the latest revision
    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)

    assert map_size(flow.definition["localization"]) == 2
    assert map_size(flow.definition["localization"]["hi"]) == 6
    assert map_size(flow.definition["localization"]["en"]) == 6
  end
end
