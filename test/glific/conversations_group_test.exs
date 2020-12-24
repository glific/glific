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

    test "list_conversations/2 will return a list with messages filtered by opts" do
      messages_limit = 1

      [c1, c2] =
        ConversationsGroup.list_conversations(nil, %{
          filter: %{search_group: true},
          contact_opts: %{limit: 10, offset: 0},
          message_opts: %{limit: messages_limit, offset: 0}
        })

      assert length(c1.messages) == messages_limit
      assert length(c2.messages) == messages_limit
    end

    test "list_conversations/2 will return a list with groups filtered by opts" do
      conversations =
        ConversationsGroup.list_conversations(nil, %{
          filter: %{search_group: true},
          contact_opts: %{limit: 1, offset: 0},
          message_opts: %{limit: 1, offset: 0}
        })

      assert length(conversations) == 1

      conversations =
        ConversationsGroup.list_conversations(nil, %{
          filter: %{search_group: true},
          contact_opts: %{limit: 1, offset: 2},
          message_opts: %{limit: 1, offset: 0}
        })

      assert conversations == []
    end
  end
end
