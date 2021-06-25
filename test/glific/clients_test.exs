defmodule Glific.ClientsTest do
  use Glific.DataCase

  alias Glific.{
    Clients,
    Clients.ReapBenefit,
    Clients.Sol,
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

  test "gcs_file_name with contact id" do
    directory =
      Clients.gcs_file_name(%{
        "organization_id" => 1,
        "contact_id" => 2,
        "remote_name" => "remote"
      })

    assert !String.contains?(directory, "/")

    directory =
      Clients.gcs_file_name(%{
        "organization_id" => 43,
        "contact_id" => 1,
        "remote_name" => "remote"
      })

    assert !String.contains?(directory, "/")

    cg = Fixtures.contact_group_fixture(%{organization_id: 1})

    directory =
      Clients.gcs_file_name(%{
        "organization_id" => 1,
        "contact_id" => cg.contact_id,
        "remote_name" => "remote"
      })

    assert String.contains?(directory, "/")

    # ensure sol works
    contact = Fixtures.contact_fixture()
    directory = Sol.gcs_file_name(%{"contact_id" => contact.id})
    assert String.contains?(directory, "/")
    assert String.contains?(directory, contact.name)

    contact = Fixtures.contact_fixture(%{name: ""})
    directory = Sol.gcs_file_name(%{"contact_id" => contact.id})
    assert String.contains?(directory, "/")
    assert String.contains?(directory, "NO NAME")

    # also test reap_benefit separately
    directory = ReapBenefit.gcs_file_name(%{"flow_id" => 1, "remote_name" => "foo"})

    assert directory == "Help Workflow/foo"

    directory = ReapBenefit.gcs_file_name(%{"flow_id" => 23, "remote_name" => "foo"})

    assert directory == "foo"
  end

  test "check blocked only allow US and India numbers" do
    assert Clients.blocked?("91123", 1) == false
    assert Clients.blocked?("1123", 1) == false
    assert Clients.blocked?("44123", 1) == false
    assert Clients.blocked?("256123", 1) == false
    assert Clients.blocked?("255123", 1) == true
    assert Clients.blocked?("925123", 1) == true
    assert Clients.blocked?("255123", 2) == false
    assert Clients.blocked?("256123", 2) == false
    assert Clients.blocked?("56123", 2) == false
    assert Clients.blocked?("9256123", 2) == false
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

  test "check that webhook always returns a map" do
    # a contact not in any group should return the same staff id
    assert is_map Clients.webhook("daily", %{fields: "some fields"})
    assert {:error, message} ==  Clients.webhook("function", %{fields: "some fields"})
    assert is_binary(message)
  end

end
