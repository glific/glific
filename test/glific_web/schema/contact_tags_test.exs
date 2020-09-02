defmodule GlificWeb.Schema.ContactTagsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts.Contact,
    Repo,
    Seeds.SeedsDev,
    Tags
  }

  setup do
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    :ok
  end

  load_gql(:update, GlificWeb.Schema, "assets/gql/contact_tags/update.gql")

  def tag_status_map(org_id) do
    Tags.status_map(%{organization_id: org_id})
  end

  test "update a contact tag with add tags", %{user: user} do
    tags_map = tag_status_map(user.organization_id)
    name = "Default receiver"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "contact_id" => contact.id,
            "add_tag_ids" => Map.values(tags_map),
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    contact_tags = get_in(query_data, [:data, "updateContactTags", "contactTags"])
    assert length(contact_tags) == length(Map.values(tags_map))

    # add a known tag id not there in the DB (like a negative number?)
    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "contact_id" => contact.id,
            "add_tag_ids" => Map.values(tags_map) ++ ["-1"],
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    contact_tags = get_in(query_data, [:data, "updateContactTags", "contactTags"])
    assert length(contact_tags) == length(Map.values(tags_map))

    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "contact_id" => contact.id,
            "add_tag_ids" => ["-1"],
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    contact_tags = get_in(query_data, [:data, "updateContactTags", "contactTags"])
    assert contact_tags == []
  end

  test "update a contact tag with add and delete tags", %{user: user} do
    tags_map = tag_status_map(user.organization_id)
    name = "Default receiver"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    # add some tags, test bad deletion value
    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "contact_id" => contact.id,
            "add_tag_ids" => Map.values(tags_map),
            "delete_tag_ids" => [-1]
          }
        }
      )

    assert {:ok, query_data} = result
    contact_tags = get_in(query_data, [:data, "updateContactTags", "contactTags"])
    assert length(contact_tags) == length(Map.values(tags_map))
    assert 0 == get_in(query_data, [:data, "updateContactTags", "numberDeleted"])

    # now delete all the added tags
    result =
      query_gql_by(:update,
        variables: %{
          "input" => %{
            "contact_id" => contact.id,
            "add_tag_ids" => [],
            "delete_tag_ids" => Map.values(tags_map)
          }
        }
      )

    assert {:ok, query_data} = result
    contact_tags = get_in(query_data, [:data, "updateContactTags", "contactTags"])
    assert Enum.empty?(contact_tags)
  end
end
