defmodule GlificWeb.Schema.TemplateTagTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Repo,
    Seeds.SeedsDev,
    Tags.Tag
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/template_tag/create.gql")

  test "create a template tag and test possible scenarios and errors", %{user: user} do
    template = Fixtures.session_template_fixture()

    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"templateId" => template.id, "tagId" => tag.id}}
      )

    assert {:ok, query_data} = result

    template_tag = get_in(query_data, [:data, "createTemplateTag", "template_tag"])
    assert template_tag["template"]["id"] |> String.to_integer() == template.id
    assert template_tag["tag"]["id"] |> String.to_integer() == tag.id

    # try creating the same template tag twice
    # upserts come into play here and we dont return an error
    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"template_id" => template.id, "tag_id" => tag.id}}
      )

    assert {:ok, query_data} = result

    template_tag = get_in(query_data, [:data, "createTemplateTag", "template_tag"])
    assert get_in(template_tag, ["template", "id"]) |> String.to_integer() == template.id
    assert get_in(template_tag, ["tag", "id"]) |> String.to_integer() == tag.id
  end
end
