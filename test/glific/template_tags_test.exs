defmodule Glific.TemplateTagsTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Seeds.SeedsDev,
    Tags.TemplateTags
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  test "lets check the edge cases first, no tags, or some crappy tags", attrs do
    template = Fixtures.session_template_fixture(attrs)

    template_tags =
      TemplateTags.update_template_tags(%{
        template_id: template.id,
        add_tag_ids: [],
        delete_tag_ids: []
      })

    assert %TemplateTags{} == template_tags
    assert template_tags.template_tags == []
    assert template_tags.number_deleted == 0

    template_tags =
      TemplateTags.update_template_tags(%{
        template_id: template.id,
        add_tag_ids: [12_345, 765_843],
        delete_tag_ids: [12_345, 765_843]
      })

    assert template_tags.template_tags == []
    assert template_tags.number_deleted == 0
  end

  test "lets check we can add all the status tags to the template", attrs do
    template = Fixtures.session_template_fixture(attrs)
    tag_1 = Fixtures.tag_fixture(attrs)
    tag_2 = Fixtures.tag_fixture(attrs |> Map.merge(%{shortcode: "newshortcode"}))

    template_tags =
      TemplateTags.update_template_tags(%{
        template_id: template.id,
        add_tag_ids: [tag_1.id, tag_2.id],
        delete_tag_ids: []
      })

    assert length(template_tags.template_tags) == 2

    # add a random unknown tag_id, and ensure we dont barf
    template_tags =
      TemplateTags.update_template_tags(%{
        template_id: template.id,
        add_tag_ids: [tag_1.id, tag_2.id] ++ ["-1"],
        delete_tag_ids: []
      })

    assert length(template_tags.template_tags) == 2

    # now delete all the added tags
    template_tags =
      TemplateTags.update_template_tags(%{
        template_id: template.id,
        add_tag_ids: [],
        delete_tag_ids: [tag_1.id, tag_2.id]
      })

    assert template_tags.template_tags == []
    assert template_tags.number_deleted == 2
  end
end
