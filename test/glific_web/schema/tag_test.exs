defmodule GlificWeb.Schema.Query.TagTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  # the number of tags we ship with by default
  @tag_count 18

  setup do
    lang = Glific.Seeds.seed_language()
    Glific.Seeds.seed_tag(lang)
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/tags/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/tags/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/tags/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/tags/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/tags/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/tags/delete.gql")

  test "tags field returns list of tags" do
    result = query_gql_by(:list, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0
    [tag | _] = tags
    assert get_in(tag, ["label"]) == "Child"

    # lets ensure that the language field exists and has a valid id
    assert get_in(tag, ["language", "id"]) > 0
  end

  test "tags field returns list of tags in desc order" do
    result = query_gql_by(:list, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result

    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    [tag | _] = tags
    assert get_in(tag, ["label"]) == "User"
  end

  test "tags field returns list of tags in various filters" do
    result = query_gql_by(:list, variables: %{"filter" => %{"label" => "Messages"}})
    assert {:ok, query_data} = result

    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    [tag | _] = tags
    assert get_in(tag, ["label"]) == "Messages"

    # get language_id for next test
    parent_id = String.to_integer(get_in(tag, ["id"]))
    language_id = String.to_integer(get_in(tag, ["language", "id"]))

    result = query_gql_by(:list, variables: %{"filter" => %{"parent" => "messages"}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    result = query_gql_by(:list, variables: %{"filter" => %{"parentId" => parent_id}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    result = query_gql_by(:list, variables: %{"filter" => %{"languageId" => language_id}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0

    result = query_gql_by(:list, variables: %{"filter" => %{"language" => "English"}})
    assert {:ok, query_data} = result
    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) > 0
  end

  test "tags field obeys limit and offset" do
    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})
    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "tags"])) == 1

    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})
    assert {:ok, query_data} = result

    tags = get_in(query_data, [:data, "tags"])
    assert length(tags) == 3

    # lets make sure we dont get child as a tag
    assert get_in(tags, [Access.at(0), "label"]) != "Child"
    assert get_in(tags, [Access.at(1), "label"]) != "Child"
    assert get_in(tags, [Access.at(2), "label"]) != "Child"
  end

  test "count returns the number of tags" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countTags"]) == @tag_count

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"label" => "This tag should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countTags"]) == 0

    {:ok, query_data} = query_gql_by(:count, variables: %{"filter" => %{"label" => "Greeting"}})
    assert get_in(query_data, [:data, "countTags"]) == 1
  end

  test "tag id returns one tag or nil" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})

    result = query_gql_by(:by_id, variables: %{"id" => tag.id})
    assert {:ok, query_data} = result

    tag = get_in(query_data, [:data, "tag", "tag", "label"])
    assert tag == label

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "tag", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a tag and test possible scenarios and errors" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    language_id = tag.language_id

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"label" => "Test Tag", "languageId" => language_id}}
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createTag", "tag", "label"])
    assert label == "Test Tag"

    # try creating the same tag twice
    _ =
      query_gql_by(:create,
        variables: %{"input" => %{"label" => "Klingon", "languageId" => language_id}}
      )

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"label" => "Klingon", "languageId" => language_id}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createTag", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update a tag and test possible scenarios and errors" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})

    result =
      query_gql_by(:update,
        variables: %{"id" => tag.id, "input" => %{"label" => "New Test Tag Label"}}
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateTag", "tag", "label"])
    assert label == "New Test Tag Label"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => tag.id,
          "input" => %{"label" => "Greeting"}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateTag", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "create a tag with keywords" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})
    language_id = tag.language_id
    keywords = ["Hii", "Hello"]

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "label" => "Keyword tag",
            "languageId" => language_id,
            "keywords" => keywords
          }
        }
      )

    assert {:ok, query_data} = result
    assert ["hii", "hello"] == get_in(query_data, [:data, "createTag", "tag", "keywords"])
  end

  test "delete a tag" do
    label = "This is for testing"
    {:ok, tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: label})

    result = query_gql_by(:delete, variables: %{"id" => tag.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteTag", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => tag.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteTag", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
