defmodule GlificWeb.Schema.TagTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Repo,
    Seeds.SeedsDev,
    Tags,
    Tags.Tag
  }

  setup do
    SeedsDev.seed_tag()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/tags/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/tags/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/tags/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/tags/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/tags/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/tags/delete.gql")

  load_gql(
    :mark_contact_messages_as_read,
    GlificWeb.Schema,
    "assets/gql/tags/mark_contact_messages_as_read.gql"
  )

  test "tags field returns list of tags", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0
    [tag | _] = tags
    assert get_in(tag, ["label"]) == "Activities"

    # lets ensure that the language field exists and has a valid id
    assert get_in(tag, ["language", "id"]) > 0
  end

  test "tags field returns list of tags in desc order", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result

    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    [tag | _] = tags
    assert get_in(tag, ["label"]) == "यह परीक्षण के लिए है"
  end

  test "tags field returns list of tags in various filters", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"label" => "Messages"}})
    assert {:ok, query_data} = result

    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    [tag | _] = tags
    assert get_in(tag, ["label"]) == "Messages"

    # get language_id for next test
    parent_id = String.to_integer(get_in(tag, ["id"]))
    language_id = String.to_integer(get_in(tag, ["language", "id"]))

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"parent" => "messages"}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"parentId" => parent_id}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    result =
      auth_query_gql_by(:list, user, variables: %{"filter" => %{"languageId" => language_id}})

    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"language" => "Hindi"}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0
  end

  test "tags field obeys limit and offset", %{staff: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "tags"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})

    assert {:ok, query_data} = result

    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) == 3

    # lets make sure we dont get Activities as a tag
    assert get_in(tags, [Access.at(0), "label"]) != "Activities"
    assert get_in(tags, [Access.at(1), "label"]) != "Activities"
    assert get_in(tags, [Access.at(2), "label"]) != "Activities"
  end

  test "count returns the number of tags", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countTags"]) > 15

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"label" => "This tag should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countTags"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"label" => "Greeting"}})

    assert get_in(query_data, [:data, "countTags"]) == 1
  end

  test "tag id returns one tag or nil", %{staff: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => tag.id})
    assert {:ok, query_data} = result

    tag = get_in(query_data, [:data, "tag", "tag", "label"])
    assert tag == label

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "tag", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a tag and test possible scenarios and errors", %{manager: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})
    language_id = tag.language_id

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Test Tag",
            "shortcode" => "testtag",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createTag", "tag", "label"])
    assert label == "Test Tag"

    # try creating the same tag twice
    _ =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Klingon",
            "shortcode" => "klingon",
            "languageId" => language_id
          }
        }
      )

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Klingon",
            "shortcode" => "klingon",
            "languageId" => language_id
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createTag", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update a tag and test possible scenarios and errors", %{manager: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => tag.id,
          "input" => %{"label" => "New Test Tag Label", "shortcode" => "newtesttaglabel"}
        }
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateTag", "tag", "label"])
    assert label == "New Test Tag Label"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => tag.id,
          "input" => %{"label" => "Greeting", "shortcode" => "greeting"}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateTag", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "create a tag with keywords", %{manager: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})
    language_id = tag.language_id
    keywords = ["Hii", "Hello"]

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "label" => "Keyword tag",
            "shortcode" => "keywordtag",
            "languageId" => language_id,
            "keywords" => keywords
          }
        }
      )

    assert {:ok, query_data} = result
    assert ["hii", "hello"] == get_in(query_data, [:data, "createTag", "tag", "keywords"])
  end

  test "delete a tag", %{manager: user} do
    label = "This is for testing"
    {:ok, tag} = Repo.fetch_by(Tag, %{label: label, organization_id: user.organization_id})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => tag.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteTag", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => tag.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteTag", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "mark all contact messages as unread", %{staff: user} do
    message_1 = Fixtures.message_fixture()

    message_2 =
      Fixtures.message_fixture(%{
        sender_id: message_1.contact_id,
        receiver_id: message_1.receiver_id
      })

    message_3 =
      Fixtures.message_fixture(%{
        sender_id: message_1.contact_id,
        receiver_id: message_1.receiver_id
      })

    {:ok, tag} = Repo.fetch_by(Tag, %{shortcode: "unread", organization_id: user.organization_id})

    message1_tag =
      Fixtures.message_tag_fixture(%{
        message_id: message_1.id,
        tag_id: tag.id,
        organization_id: user.organization_id
      })

    message2_tag =
      Fixtures.message_tag_fixture(%{
        message_id: message_2.id,
        tag_id: tag.id,
        organization_id: user.organization_id
      })

    message3_tag =
      Fixtures.message_tag_fixture(%{
        message_id: message_3.id,
        tag_id: tag.id,
        organization_id: user.organization_id
      })

    result =
      auth_query_gql_by(:mark_contact_messages_as_read, user,
        variables: %{"contactId" => Integer.to_string(message_1.contact_id)}
      )

    assert {:ok, query_data} = result

    untag_message_id = get_in(query_data, [:data, "markContactMessagesAsRead"])

    assert untag_message_id != nil

    assert Integer.to_string(message_1.id) in untag_message_id
    assert Integer.to_string(message_2.id) in untag_message_id
    assert Integer.to_string(message_3.id) in untag_message_id

    assert_raise Ecto.NoResultsError, fn -> Tags.get_message_tag!(message1_tag.id) end
    assert_raise Ecto.NoResultsError, fn -> Tags.get_message_tag!(message2_tag.id) end
    assert_raise Ecto.NoResultsError, fn -> Tags.get_message_tag!(message3_tag.id) end
  end
end
