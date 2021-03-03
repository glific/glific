defmodule Glific.ClientsTest do
  use Glific.DataCase

  alias Glific.{
    Clients,
    Fixtures,
  }

  test "plugins returns the right value for test vs prod" do
    map = Clients.plugins()
    assert Enum.count(map) == 1 # only the main organization is returned

    map = Clients.plugins(:prod)
    assert Enum.count(map) > 1 # we at least have STiR and TAP
  end

  test "gcs_bucket with contact id" do
    bucket = Clients.gcs_bucket(%{"organization_id" => 1, "contact_id" => 2}, "default")
    assert bucket == "default"

    bucket = Clients.gcs_bucket(%{"organization_id" => 43, "contact_id" => 1}, "default")
    assert bucket == "default"

    cg = Fixtures.contact_group_fixture(%{organization_id: 1})
    bucket = Clients.gcs_bucket(%{"organization_id" => 1, "contact_id" => cg.contact_id}, "default")
    assert bucket != "default"
  end

  test "check blocked only allow US and India numbers" do
    assert Clients.blocked?("91123", 1) == false
    assert Clients.blocked?("1123", 1) == false
    assert Clients.blocked?("44123", 1) == true
    assert Clients.blocked?("44123", 2) == false
  end
end
