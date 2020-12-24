defmodule Glific.ConversationsGroupTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    ConversationsGroup,
    Fixtures,
    Groups,
    Seeds.SeedsDev
  }

  describe "conversations group" do
    setup do
      default_provider = SeedsDev.seed_providers()
      SeedsDev.seed_organizations(default_provider)
      SeedsDev.seed_contacts()
      :ok
    end

    test "list_conversations/2 will return a list of conversation objects with group", attrs do
      Fixtures.group_messages_fixture(attrs)

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

    test "list_conversations/2 will return a list with messages filtered by opts", attrs do
      Fixtures.group_messages_fixture(attrs)

      [c1, c2 | _] =
        ConversationsGroup.list_conversations(nil, %{
          filter: %{search_group: true},
          contact_opts: %{limit: 10, offset: 0},
          message_opts: %{limit: 1, offset: 0}
        })

      assert length(c1.messages) == 1
      assert length(c2.messages) == 1
    end

    test "list_conversations/2 will return a list with groups filtered by opts", attrs do
      Fixtures.group_messages_fixture(attrs)
      groups = Groups.list_groups(%{filter: attrs})

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
          contact_opts: %{limit: 1, offset: length(groups)},
          message_opts: %{limit: 1, offset: 0}
        })

      assert conversations == []
    end
  end
end
