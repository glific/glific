defmodule Glific.ClientsTest do
  use Glific.DataCase

  alias Glific.{
    Clients,
    Contacts,
    Fixtures
  }

  test "plugins returns the right value for test vs prod" do
    map = Clients.plugins()
    # only the main organization is returned
    assert Enum.count(map) == 1

    map = Clients.plugins(:prod)
    # we at least have STiR and TAP
    assert Enum.count(map) > 1
  end

  test "gcs_params with contact id" do
    {directory, _bucket} = Clients.gcs_params(
      %{"organization_id" => 1, "contact_id" => 2, "remote_name" => "remote"},
      "default")
    assert !String.contains?(directory, "/")

    {directory, _bucket} = Clients.gcs_params(
      %{"organization_id" => 43, "contact_id" => 1, "remote_name" => "remote"},
      "default")
    assert !String.contains?(directory, "/")

    cg = Fixtures.contact_group_fixture(%{organization_id: 1})

    {directory, _bucket} =
      Clients.gcs_params(
        %{"organization_id" => 1, "contact_id" => cg.contact_id, "remote_name" => "remote"},
        "default")

    assert String.contains?(directory, "/")
  end

  test "check blocked only allow US and India numbers" do
    assert Clients.blocked?("91123", 1) == false
    assert Clients.blocked?("1123", 1) == false
    assert Clients.blocked?("44123", 1) == true
    assert Clients.blocked?("44123", 2) == false
  end

  test "check that broadcast returns a different staff id" do
    contact = Fixtures.contact_fixture()

    # a contact not in any group should return the same staff id
    assert Clients.broadcast(nil, contact, 100) == 100

    # lets munge organization_id
    assert Clients.broadcast(nil, Map.put(contact, :organization_id, 103), 107) == 107

    # now lets create a contact group and a user group
    {cg, ug} = Fixtures.contact_user_group_fixture(%{organization_id: 1})
    contact = Contacts.get_contact!(cg.contact_id)
    assert Clients.broadcast(nil, contact, -1) == ug.user.contact_id
  end
end
