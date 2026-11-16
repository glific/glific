defmodule GlificWeb.Schema.ContactTagsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Repo,
    Seeds.SeedsDev,
    Tags,
    Tags.ContactTag
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

  test "update a contact tag with add tags", %{staff: user} do
    tags_map = tag_status_map(user.organization_id)
    name = "Default receiver"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
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
      auth_query_gql_by(:update, user,
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
      auth_query_gql_by(:update, user,
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

  test "update a contact tag with add and delete tags", %{staff: user} do
    tags_map = tag_status_map(user.organization_id)
    name = "Default receiver"
    {:ok, contact} = Repo.fetch_by(Contact, %{name: name, organization_id: user.organization_id})

    # add some tags, test bad deletion value
    result =
      auth_query_gql_by(:update, user,
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
      auth_query_gql_by(:update, user,
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

  describe "cross-organization access" do
    setup %{staff: user} do
      other_organization =
        Fixtures.organization_fixture(%{shortcode: "other_organization_contact_tags"})

      Repo.put_organization_id(other_organization.id)
      other_contact = Fixtures.contact_fixture(%{organization_id: other_organization.id})
      other_tag = Fixtures.tag_fixture(%{organization_id: other_organization.id})
      Repo.put_organization_id(user.organization_id)

      {:ok, contact} =
        Repo.fetch_by(Contact, %{name: "Default receiver", organization_id: user.organization_id})

      %{contact: contact, other_contact: other_contact, other_tag: other_tag}
    end

    test "does not add another organization's tag", %{
      staff: user,
      contact: contact,
      other_tag: other_tag
    } do
      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "contact_id" => contact.id,
              "add_tag_ids" => [other_tag.id],
              "delete_tag_ids" => []
            }
          }
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "updateContactTags", "contactTags"]) == []
      refute Repo.exists?(ContactTag |> where(tag_id: ^other_tag.id), skip_organization_id: true)
    end

    test "rejects another organization's contact", %{
      staff: user,
      other_contact: other_contact
    } do
      tag_ids = user.organization_id |> tag_status_map() |> Map.values()

      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "contact_id" => other_contact.id,
              "add_tag_ids" => tag_ids,
              "delete_tag_ids" => []
            }
          }
        )

      assert {:ok, query_data} = result

      assert [%{"message" => message}] =
               get_in(query_data, [:data, "updateContactTags", "errors"])

      assert message =~ "Resource not found"

      refute Repo.exists?(ContactTag |> where(contact_id: ^other_contact.id),
               skip_organization_id: true
             )
    end
  end
end
