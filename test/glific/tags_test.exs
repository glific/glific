defmodule Glific.TagsTest do
  use Glific.DataCase

  alias Glific.Fixtures, ["contact"]

  alias Glific.{Settings, Tags, Tags.Tag}



  describe "tags" do
    # language id needs to be added dynamically for all the below actions
    @valid_attrs %{
      label: "some label",
      description: "some description",
      locale: "en_US",
      is_active: true,
      is_reserved: true
    }
    @valid_more_attrs %{
      label: "hindi more label",
      description: " more description",
      locale: "hi_US",
      is_active: true,
      is_reserved: true
    }
    @update_attrs %{
      label: "some updated label",
      description: "some updated description",
      is_active: false,
      is_reserved: false
    }
    @invalid_attrs %{
      label: nil,
      description: nil,
      is_active: nil,
      is_reserved: nil,
      language_id: nil
    }

    @valid_language_attrs %{
      label: "English (United States)",
      locale: "en_US",
      is_active: true
    }
    @valid_hindi_attrs %{
      label: "Hindi (United States)",
      locale: "hi_US",
      is_active: true
    }

    def language_fixture(attrs \\ %{}) do
      {:ok, language} =
        attrs
        |> Enum.into(@valid_language_attrs)
        |> Settings.create_language()

      language
    end

    def tag_fixture(attrs \\ %{}) do
      language = language_fixture(attrs)

      {:ok, tag} =
        attrs
        |> Map.put(:language_id, language.id)
        |> Enum.into(@valid_attrs)
        |> Tags.create_tag()

      tag
    end

    test "list_tags/0 returns all tags" do
      tag = tag_fixture()
      assert Tags.list_tags() == [tag]
    end

    test "get_tag!/1 returns the tag with given id" do
      tag = tag_fixture()
      assert Tags.get_tag!(tag.id) == tag
    end

    test "create_tag/1 with valid data creates a tag" do
      language = language_fixture()
      attrs = Map.merge(@valid_attrs, %{language_id: language.id})
      assert {:ok, %Tag{} = tag} = Tags.create_tag(attrs)
      assert tag.description == "some description"
      assert tag.is_active == true
      assert tag.is_reserved == true
      assert tag.label == "some label"
      assert tag.language_id == language.id
    end

    test "create_tag/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tags.create_tag(@invalid_attrs)
    end

    test "update_tag/2 with valid data updates the tag" do
      tag = tag_fixture()
      language = language_fixture(@valid_hindi_attrs)
      attrs = Map.merge(@update_attrs, %{language_id: language.id})
      assert {:ok, %Tag{} = tag} = Tags.update_tag(tag, attrs)
      assert tag.description == "some updated description"
      assert tag.is_active == false
      assert tag.is_reserved == false
      assert tag.label == "some updated label"
      assert tag.language_id == language.id
    end

    test "update_tag/2 with invalid data returns error changeset" do
      tag = tag_fixture()
      assert {:error, %Ecto.Changeset{}} = Tags.update_tag(tag, @invalid_attrs)
      assert tag == Tags.get_tag!(tag.id)
    end

    test "delete_tag/1 deletes the tag" do
      tag = tag_fixture()
      assert {:ok, %Tag{}} = Tags.delete_tag(tag)
      assert_raise Ecto.NoResultsError, fn -> Tags.get_tag!(tag.id) end
    end

    test "change_tag/1 returns a tag changeset" do
      tag = tag_fixture()
      assert %Ecto.Changeset{} = Tags.change_tag(tag)
    end

    test "list_tags/1 with multiple items" do
      tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags()
      assert length(tags) == 2
      [h, t | _] = tags
      assert (h == tag1 && t == tag2) || (h == tag2 && t == tag1)
    end

    test "list_tags/1 with multiple items sorted" do
      tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{order: :asc})
      assert length(tags) == 2
      [h, t | _] = tags
      assert h == tag2 && t == tag1
    end

    test "list_tags/1 with items filtered" do
      _tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{order: :asc, filter: %{label: "more label"}})
      assert length(tags) == 1
      [h] = tags
      assert h == tag2
    end

    test "list_tags/1 with language filtered" do
      _tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{order: :asc, filter: %{language: "hindi"}})
      assert length(tags) == 1
      [h] = tags
      assert h == tag2
    end

    test "create_tags fails with constraint violation on language" do
      language = language_fixture()
      attrs = Map.merge(@valid_attrs, %{language_id: language.id * 10})
      assert {:error, %Ecto.Changeset{}} = Tags.create_tag(attrs)
    end
  end

  describe "messages_tags" do
    @valid_attrs %{
      label: "some label",
      description: "some description",
      locale: "en_US",
      is_active: true,
      is_reserved: true
    }
    @valid_more_attrs %{
      label: "hindi more label",
      description: " more description",
      locale: "hi_US",
      is_active: true,
      is_reserved: true
    }
    @update_attrs %{
      label: "some updated label",
      description: "some updated description",
      is_active: false,
      is_reserved: false
    }
    @invalid_attrs %{
      label: nil,
      description: nil,
      is_active: nil,
      is_reserved: nil,
      language_id: nil
    }

    @valid_language_attrs %{
      label: "English (United States)",
      locale: "en_US",
      is_active: true
    }
    @valid_hindi_attrs %{
      label: "Hindi (United States)",
      locale: "hi_US",
      is_active: true
    }

    def message_tag_fixture(attrs \\ %{}) do
      {:ok, language} =
        attrs
        |> Enum.into(@valid_language_attrs)
        |> Settings.create_language()

      language
    end

    def tag_fixture(attrs \\ %{}) do
      language = language_fixture(attrs)

      {:ok, tag} =
        attrs
        |> Map.put(:language_id, language.id)
        |> Enum.into(@valid_attrs)
        |> Tags.create_tag()

      tag
    end

    test "list_tags/0 returns all tags" do
      tag = tag_fixture()
      assert Tags.list_tags() == [tag]
    end

    test "get_tag!/1 returns the tag with given id" do
      tag = tag_fixture()
      assert Tags.get_tag!(tag.id) == tag
    end

    test "create_tag/1 with valid data creates a tag" do
      language = language_fixture()
      attrs = Map.merge(@valid_attrs, %{language_id: language.id})
      assert {:ok, %Tag{} = tag} = Tags.create_tag(attrs)
      assert tag.description == "some description"
      assert tag.is_active == true
      assert tag.is_reserved == true
      assert tag.label == "some label"
      assert tag.language_id == language.id
    end

    test "create_tag/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tags.create_tag(@invalid_attrs)
    end

    test "update_tag/2 with valid data updates the tag" do
      tag = tag_fixture()
      language = language_fixture(@valid_hindi_attrs)
      attrs = Map.merge(@update_attrs, %{language_id: language.id})
      assert {:ok, %Tag{} = tag} = Tags.update_tag(tag, attrs)
      assert tag.description == "some updated description"
      assert tag.is_active == false
      assert tag.is_reserved == false
      assert tag.label == "some updated label"
      assert tag.language_id == language.id
    end

    test "update_tag/2 with invalid data returns error changeset" do
      tag = tag_fixture()
      assert {:error, %Ecto.Changeset{}} = Tags.update_tag(tag, @invalid_attrs)
      assert tag == Tags.get_tag!(tag.id)
    end

    test "delete_tag/1 deletes the tag" do
      tag = tag_fixture()
      assert {:ok, %Tag{}} = Tags.delete_tag(tag)
      assert_raise Ecto.NoResultsError, fn -> Tags.get_tag!(tag.id) end
    end

    test "change_tag/1 returns a tag changeset" do
      tag = tag_fixture()
      assert %Ecto.Changeset{} = Tags.change_tag(tag)
    end

    test "list_tags/1 with multiple items" do
      tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags()
      assert length(tags) == 2
      [h, t | _] = tags
      assert (h == tag1 && t == tag2) || (h == tag2 && t == tag1)
    end

    test "list_tags/1 with multiple items sorted" do
      tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{order: :asc})
      assert length(tags) == 2
      [h, t | _] = tags
      assert h == tag2 && t == tag1
    end

    test "list_tags/1 with items filtered" do
      _tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{order: :asc, filter: %{label: "more label"}})
      assert length(tags) == 1
      [h] = tags
      assert h == tag2
    end

    test "list_tags/1 with language filtered" do
      _tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{order: :asc, filter: %{language: "hindi"}})
      assert length(tags) == 1
      [h] = tags
      assert h == tag2
    end

    test "create_tags fails with constraint violation on language" do
      language = language_fixture()
      attrs = Map.merge(@valid_attrs, %{language_id: language.id * 10})
      assert {:error, %Ecto.Changeset{}} = Tags.create_tag(attrs)
    end
  end
end
