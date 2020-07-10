defmodule Glific.MessageTagsTest do
  use Glific.DataCase

  alias Glific.{Fixtures, Tags, Tags.MessageTags}

  setup do
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_tag()
    :ok
  end

  test "lets check the edge cases first, no tags, or some crappy tags" do
    message = Fixtures.message_fixture()

    message_tags =
      MessageTags.update_message_tags(%{
        message_id: message.id,
        add_tag_ids: [],
        delete_tag_ids: []
      })

    assert message_tags.message_tags == []
    assert message_tags.number_deleted == 0

    message_tags =
      MessageTags.update_message_tags(%{
        message_id: message.id,
        add_tag_ids: [12_345, 765_843],
        delete_tag_ids: [12_345, 765_843]
      })

    assert message_tags.message_tags == []
    assert message_tags.number_deleted == 0
  end

  test "lets check we can add all the status tags to the message" do
    message = Fixtures.message_fixture()
    tags_map = Tags.status_map()

    message_tags =
      MessageTags.update_message_tags(%{
        message_id: message.id,
        add_tag_ids: Map.values(tags_map),
        delete_tag_ids: []
      })

    assert length(message_tags.message_tags) == length(Map.values(tags_map))

    # add a random unknown tag_id, and ensure we dont barf
    message_tags =
      MessageTags.update_message_tags(%{
        message_id: message.id,
        add_tag_ids: Map.values(tags_map) ++ ["-1"],
        delete_tag_ids: []
      })

    assert length(message_tags.message_tags) == length(Map.values(tags_map))

    # now delete all the added tags
    message_tags =
      MessageTags.update_message_tags(%{
        message_id: message.id,
        add_tag_ids: [],
        delete_tag_ids: Map.values(tags_map)
      })

    assert message_tags.message_tags == []
    assert message_tags.number_deleted == length(Map.values(tags_map))
  end
end
