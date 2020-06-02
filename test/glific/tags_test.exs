defmodule Glific.TagsTest do
  use Glific.DataCase

  alias Glific.{Tags, Settings}

  describe "tags" do
    alias Glific.Tags.Tag

    # language id needs to be added dynamically for all the below actions
    @valid_attrs %{
      description: "some description",
      is_active: true,
      is_reserved: true,
      label: "some label",
    }
    @update_attrs %{
      description: "some updated description",
      is_active: false,
      is_reserved: false,
      label: "some updated label",
    }
    @invalid_attrs %{
      description: nil,
      is_active: nil,
      is_reserved: nil,
      label: nil,
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
      language = language_fixture()

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
      attrs = Map.merge(@valid_attrs, %{language_id: language.id});
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
      attrs = Map.merge(@update_attrs, %{language_id: language.id});
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
  end
end
