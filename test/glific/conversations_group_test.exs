defmodule Glific.ConversationsGroupTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    ConversationsGroup,
    Groups,
    Seeds.SeedsDev
  }

  describe "conversations group" do
    setup do
      default_provider = SeedsDev.seed_providers()
      SeedsDev.seed_organizations(default_provider)
      SeedsDev.seed_contacts()
      SeedsDev.seed_messages()
      SeedsDev.seed_groups()
      SeedsDev.seed_group_contacts()
      SeedsDev.seed_group_messages()
      :ok
    end

    test "list_conversations/2 will return a list of conversation objects with group", attrs do
      conversations =
        ConversationsGroup.list_conversations(nil, %{
          filter: %{search_group: true},
          contact_opts: %{limit: 10, offset: 0},
          message_opts: %{limit: 10, offset: 0}
        })

      assert length(conversations) >= 1

      # if group_ids are passed, it should list conversation with those groups only
      [group | _] = Groups.list_groups(%{filter: attrs})

      conversations =
        ConversationsGroup.list_conversations([group.id], %{
          filter: %{search_group: true},
          contact_opts: %{limit: 10, offset: 0},
          message_opts: %{limit: 10, offset: 0}
        })

      assert [conversation] = conversations
      assert conversation.group.id == group.id
    end
  end
end
