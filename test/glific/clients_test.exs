defmodule Glific.ClientsTest do
  use Glific.DataCase

  alias Glific.{
    Clients,
    Clients.Bandhu,
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

    # ensure Sol Works
    contact = Fixtures.contact_fixture()

    message_media = Fixtures.message_media_fixture(%{contact_id: contact.id, organization_id: 1})

    directory =
      Sol.gcs_file_name(%{
        "contact_id" => contact.id,
        "organization_id" => 1,
        "id" => message_media.id
      })

    assert String.contains?(directory, "/")
    assert String.contains?(directory, contact.phone)

    contact = Fixtures.contact_fixture(%{name: ""})

    directory =
      Sol.gcs_file_name(%{
        "contact_id" => contact.id,
        "organization_id" => 1,
        "id" => message_media.id
      })

    assert String.contains?(directory, "/")

    # also test reap_benefit separately
    directory = ReapBenefit.gcs_file_name(%{"flow_id" => 1, "remote_name" => "foo"})

    assert directory == "Help Workflow/foo"

    directory = ReapBenefit.gcs_file_name(%{"flow_id" => 23, "remote_name" => "foo"})

    assert directory == "foo"
  end

  test "check blocked allow all numbers" do
    assert Clients.blocked?("91123", 1) == false
    assert Clients.blocked?("1123", 1) == false
    assert Clients.blocked?("44123", 1) == false
    assert Clients.blocked?("256123", 1) == false
    assert Clients.blocked?("255123", 1) == false
    assert Clients.blocked?("925123", 1) == false
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
    assert is_map(Clients.webhook("daily", %{fields: "some fields"}))

    assert %{error: "Missing webhook function implementation"} ==
             Clients.webhook("function", %{fields: "some fields"})
  end

  test "fetch_user_profiles webhook function" do
    fields = %{
      "results" => %{
        "parent" => %{
          "bandhu_profile_check_mock" => %{
            "success" => "true",
            "message" => "List loaded Successfully.",
            "inserted_at" => "2024-04-18T14:19:08.110951Z",
            "data" => %{
              "profile_count" => 2,
              "profiles" => %{
                "19" => %{
                  "user_selected_language" => %{
                    "name" => "English",
                    "language_code" => "en"
                  },
                  "user_roles" => %{
                    "role_type" => "Worker",
                    "role_id" => 3
                  },
                  "name" => "Jacob Worker Odisha",
                  "mobile_no" => "809XXXXXX3",
                  "id" => 14_698,
                  "full_mobile_no" => nil
                },
                "1" => %{
                  "user_selected_language" => %{
                    "name" => "English",
                    "language_code" => "en"
                  },
                  "user_roles" => %{
                    "role_type" => "Employer",
                    "role_id" => 1
                  },
                  "name" => "Jacob Employer",
                  "mobile_no" => "809XXXXXX3",
                  "id" => 11_987,
                  "full_mobile_no" => nil
                }
              }
            }
          }
        }
      }
    }

    assert %{profile_selection_message: _, index_map: index_map} =
             Bandhu.webhook("fetch_user_profiles", fields)

    fields = %{
      "profile_number" => "1",
      "index_map" => index_map
    }

    assert %{profile: _} = Bandhu.webhook("set_contact_profile", fields)
  end
end
