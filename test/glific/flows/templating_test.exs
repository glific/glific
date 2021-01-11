defmodule Glific.Flows.TemplatingTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Flows.Templating,
    Templates
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.hsm_templates(organization)
    :ok
  end

  test "process extracts the right values from json for templating action",
       %{organization_id: organization_id} = _attrs do
    [template | _] =
      Templates.list_session_templates(%{
        filter: %{
          shortcode: "otp",
          is_hsm: true,
          organization_id: organization_id
        }
      })

    json = %{
      "template" => %{"uuid" => template.uuid, "name" => "test name"},
      "variables" => ["variable_1", "variable_2"]
    }

    {templating, uuid_map} = Templating.process(json, %{})

    assert templating.uuid == template.uuid
    assert templating.name == "test name"
    assert templating.template == template
    assert templating.variables == ["variable_1", "variable_2"]
    assert uuid_map[templating.uuid] == {:templating, templating}
  end
end
