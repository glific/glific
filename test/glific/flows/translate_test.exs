defmodule Glific.Flows.TranslateTest do
  use Glific.DataCase

  alias Glific.{
    Flows,
    Flows.Flow,
    Flows.Translate.Export,
    Flows.Translate.Import,
    Repo,
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
        assert length(row) == 5
        [type, uuid, src, dst, _node_uuid] = row
        assert type == "Action"
        assert String.length(uuid) == 36

        if not Enum.member?(
             ["e319cd39-f764-4680-9199-4cb7da647166", "a970d5d9-2951-48dc-8c66-ee6833c4b21e"],
             uuid
           ) do
          assert dst == "Hindi #{src} English"
        end
      end
    )
  end

  test "ensure that import updates the localization structure", attrs do
    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)
    assert map_size(flow.definition["localization"]) == 1
    assert map_size(flow.definition["localization"]["hi"]) == 1
    csv = Export.export_localization(flow)
    Import.import_localization(csv, flow)

    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)

    assert map_size(flow.definition["localization"]) == 2
    assert map_size(flow.definition["localization"]["hi"]) == 6
    assert map_size(flow.definition["localization"]["en"]) == 6
  end

  test "ensure that import doesn't change the attachment url", attrs do
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Media flow"})
    flow_before_import = Flows.get_complete_flow(attrs.organization_id, flow.id)

    attachment_url_before =
      get_in(flow_before_import.definition, [
        "localization",
        "hi",
        "a970d5d9-2951-48dc-8c66-ee6833c4b21e"
      ])

    csv = Export.export_localization(flow_before_import)
    Import.import_localization(csv, flow_before_import)

    flow_after_import = Flows.get_complete_flow(attrs.organization_id, flow.id)

    attachment_url_after =
      get_in(flow_after_import.definition, [
        "localization",
        "hi",
        "a970d5d9-2951-48dc-8c66-ee6833c4b21e"
      ])

    assert attachment_url_before == attachment_url_after
  end
end
