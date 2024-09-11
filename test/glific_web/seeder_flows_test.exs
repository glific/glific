defmodule GlificWeb.SeederFlowsTest do
  use ExUnit.Case
  use Glific.DataCase

  alias Glific.{
    Partners,
    Seeds.SeedsFlows,
    Repo,
    Flows.Flow
  }

  test "add_template_flows/1 should create the template flows" do
    organizations = Partners.list_organizations()
    assert SeedsFlows.add_template_flows(organizations) == :ok
  end
end
