defmodule GlificWeb.Schema.TemplateTagsTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Fixtures,
    Repo,
    Seeds.SeedsDev,
    Tags,
    Tags.TemplateTag
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

  describe "cross-organization access" do
    setup %{staff: user} do
      other_organization =
        Fixtures.organization_fixture(%{shortcode: "other_organization_template_tags"})

      Repo.put_organization_id(other_organization.id)

      other_template =
        Fixtures.session_template_fixture(%{organization_id: other_organization.id})

      other_tag = Fixtures.tag_fixture(%{organization_id: other_organization.id})
      Repo.put_organization_id(user.organization_id)

      %{
        template: Fixtures.session_template_fixture(),
        other_template: other_template,
        other_tag: other_tag
      }
    end

    test "does not add another organization's tag", %{
      staff: user,
      template: template,
      other_tag: other_tag
    } do
      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "template_id" => template.id,
              "add_tag_ids" => [other_tag.id],
              "delete_tag_ids" => []
            }
          }
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "updateTemplateTags", "templateTags"]) == []
      refute Repo.exists?(TemplateTag |> where(tag_id: ^other_tag.id), skip_organization_id: true)
    end

    test "rejects another organization's template", %{
      staff: user,
      other_template: other_template
    } do
      tag_ids = user.organization_id |> tag_status_map() |> Map.values()

      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "template_id" => other_template.id,
              "add_tag_ids" => tag_ids,
              "delete_tag_ids" => []
            }
          }
        )

      assert {:ok, query_data} = result

      assert [%{"message" => message}] =
               get_in(query_data, [:data, "updateTemplateTags", "errors"])

      assert message =~ "Resource not found"

      refute Repo.exists?(TemplateTag |> where(template_id: ^other_template.id),
               skip_organization_id: true
             )
    end
  end
end
