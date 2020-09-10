defmodule GlificWeb.Schema.TemplateTagsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Seeds.SeedsDev,
    Tags
  }

  setup do
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    Fixtures.session_template_fixture()
    :ok
  end

  load_gql(:update, GlificWeb.Schema, "assets/gql/template_tags/update.gql")

  def tag_status_map(org_id) do
    Tags.status_map(%{organization_id: org_id})
  end

  test "update a template tag with add tags", %{staff: user} do
    tags_map = tag_status_map(user.organization_id)
    template = Fixtures.session_template_fixture()

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "input" => %{
            "template_id" => template.id,
            "add_tag_ids" => Map.values(tags_map),
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    template_tags = get_in(query_data, [:data, "updateTemplateTags", "templateTags"])
    assert length(template_tags) == length(Map.values(tags_map))

    # add a known tag id not there in the DB (like a negative number?)
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "input" => %{
            "template_id" => template.id,
            "add_tag_ids" => Map.values(tags_map) ++ ["-1"],
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    template_tags = get_in(query_data, [:data, "updateTemplateTags", "templateTags"])
    assert length(template_tags) == length(Map.values(tags_map))

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "input" => %{
            "template_id" => template.id,
            "add_tag_ids" => ["-1"],
            "delete_tag_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    template_tags = get_in(query_data, [:data, "updateTemplateTags", "templateTags"])
    assert template_tags == []
  end

  test "update a template tag with add and delete tags", %{staff: user} do
    tags_map = tag_status_map(user.organization_id)
    template = Fixtures.session_template_fixture()

    # add some tags, test bad deletion value
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "input" => %{
            "template_id" => template.id,
            "add_tag_ids" => Map.values(tags_map),
            "delete_tag_ids" => [-1]
          }
        }
      )

    assert {:ok, query_data} = result
    template_tags = get_in(query_data, [:data, "updateTemplateTags", "templateTags"])
    assert length(template_tags) == length(Map.values(tags_map))
    assert 0 == get_in(query_data, [:data, "updateTemplateTags", "numberDeleted"])

    # now delete all the added tags
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "input" => %{
            "template_id" => template.id,
            "add_tag_ids" => [],
            "delete_tag_ids" => Map.values(tags_map)
          }
        }
      )

    assert {:ok, query_data} = result
    template_tags = get_in(query_data, [:data, "updateTemplateTags", "templateTags"])
    assert Enum.empty?(template_tags)
  end
end
