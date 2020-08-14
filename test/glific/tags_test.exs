defmodule Glific.TagsTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Seeds.SeedsDev,
    Settings.Language,
    Tags,
    Tags.ContactTag,
    Tags.MessageTag,
    Tags.Tag
  }

  describe "tags" do
    # language id needs to be added dynamically for all the below actions
    @valid_attrs %{
      label: "some label",
      shortcode: "some-label",
      description: "some fixed description",
      is_active: true,
      is_reserved: true
    }
    @valid_more_attrs %{
      label: "hindi some label",
      shortcode: "hindi-some-label",
      description: "some fixed description",
      is_active: true,
      is_reserved: true
    }
    @update_attrs %{
      label: "some updated label",
      shortcode: "some-updated-label",
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

    def tag_fixture(attrs \\ %{}) do
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)

      {:ok, tag} =
        attrs
        |> Map.put(:language_id, language.id)
        |> Enum.into(@valid_attrs)
        |> Tags.create_tag()

      tag
    end

    test "list_tags/0 returns all tags" do
      tag = tag_fixture()

      assert Enum.filter(
               Tags.list_tags(),
               fn t -> t.label == tag.label end
             ) ==
               [tag]
    end

    test "count_tags/0 returns count of all tags" do
      tag_count = Repo.aggregate(Tag, :count)

      _ = tag_fixture()
      assert Tags.count_tags() == tag_count + 1

      _ = tag_fixture(@valid_more_attrs)
      assert Tags.count_tags() == tag_count + 2

      assert Tags.count_tags(%{filter: %{label: "hindi some label"}}) == 1
    end

    test "get_tag!/1 returns the tag with given id" do
      tag = tag_fixture()
      assert Tags.get_tag!(tag.id) == tag
    end

    test "create_tag/1 with valid data creates a tag" do
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)

      attrs = Map.merge(@valid_attrs, %{language_id: language.id})
      assert {:ok, %Tag{} = tag} = Tags.create_tag(attrs)
      assert tag.description == "some fixed description"
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
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)
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
      tag_count = Repo.aggregate(Tag, :count)

      tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags()

      assert length(tags) == tag_count + 2

      [h, t] = Enum.filter(tags, fn t -> t.description == "some fixed description" end)
      assert (h == tag1 && t == tag2) || (h == tag2 && t == tag1)
    end

    test "list_tags/1 with multiple items sorted" do
      tag_count = Repo.aggregate(Tag, :count)

      tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{opts: %{order: :asc}})

      assert length(tags) == tag_count + 2

      [h, t] = Enum.filter(tags, fn t -> t.description == "some fixed description" end)
      assert h == tag2 && t == tag1
    end

    test "list_tags/1 with items filtered" do
      _tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{opts: %{order: :asc}, filter: %{label: "hindi some label"}})
      assert length(tags) == 1
      [h] = tags
      assert h == tag2
    end

    test "list_tags/1 with language filtered" do
      tag1 = tag_fixture()
      tag2 = tag_fixture(@valid_more_attrs)
      tags = Tags.list_tags(%{opts: %{order: :asc}, filter: %{language: "hindi"}})
      assert length(tags) == 2
      [h | [t]] = tags
      assert (h == tag2 && t == tag1) || (h == tag1 && t == tag2)
    end

    test "create_tags fails with constraint violation on language" do
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)
      attrs = Map.merge(@valid_attrs, %{language_id: language.id * 10})
      assert {:error, %Ecto.Changeset{}} = Tags.create_tag(attrs)
    end

    test "keywords can be added to tags" do
      language = Repo.fetch_by(Language, %{label: "Hindi"}) |> elem(1)
      keywords = ["Hello", "hi", "hola", "namaste", "good morning"]
      attrs = Map.merge(@valid_attrs, %{language_id: language.id, keywords: keywords})
      assert {:ok, %Tag{} = tag} = Tags.create_tag(attrs)
      assert tag.keywords == ["hello", "hi", "hola", "namaste", "good morning"]
    end

    test "keywords can be updated for a tag" do
      tag = tag_fixture()
      keywords = ["Hello", "Hi", "Hola", "Namaste"]
      attrs = Map.merge(@update_attrs, %{keywords: keywords})
      assert {:ok, %Tag{} = tag} = Tags.update_tag(tag, attrs)
      assert tag.keywords == ["hello", "hi", "hola", "namaste"]
    end

    test "keyword_map/0 returns a keyword map with ids" do
      tag = tag_fixture()
      tag2 = tag_fixture(%{label: "tag 2", shortcode: "tag-2"})

      Tags.update_tag(tag, %{
        keywords: ["Hello foobar", "hi example", "hola test", "namaste saab"]
      })

      Tags.update_tag(tag2, %{keywords: ["Tag2", "Tag21", "Tag22", "Tag23"]})
      keyword_map = Tags.keyword_map()
      assert is_map(keyword_map)
      assert keyword_map["hello foobar"] == tag.id
      assert keyword_map["tag2"] == tag2.id
    end

    test "status_map/0 returns a keyword map with ids" do
      tag = tag_fixture(%{label: "Unread", shortcode: "unread"})
      tag2 = tag_fixture(%{label: "New Contact", shortcode: "new-contact"})
      status_map = Tags.status_map()
      assert is_map(status_map)
      assert status_map["unread"] == tag.id
      assert status_map["new-contact"] == tag2.id
    end
  end

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  describe "messages_tags" do
    test "list_messages_tags/0 returns all message_tags" do
      message_tag = Fixtures.message_tag_fixture()
      assert Tags.list_messages_tags() == [message_tag]
    end

    test "get_messages_tag!/1 returns the messages_tag with given id" do
      message_tag = Fixtures.message_tag_fixture()
      assert Tags.get_message_tag!(message_tag.id) == message_tag
    end

    test "create_messages_tag/1 with valid data creates a tag" do
      message = Fixtures.message_fixture()
      tag = Fixtures.tag_fixture()
      message_tag = Fixtures.message_tag_fixture(%{message_id: message.id, tag_id: tag.id})
      assert message_tag.message_id == message.id
      assert message_tag.tag_id == tag.id
    end

    test "update_messages_tag/2 with valid data updates the tag" do
      message = Fixtures.message_fixture()
      message_tag = Fixtures.message_tag_fixture()

      assert {:ok, %MessageTag{} = message_tag} =
               Tags.update_message_tag(message_tag, %{message_id: message.id})

      assert message_tag.message_id == message.id
    end

    test "delete_messages_tag/1 deletes the tag" do
      message_tag = Fixtures.message_tag_fixture()
      assert {:ok, %MessageTag{}} = Tags.delete_message_tag(message_tag)
      assert_raise Ecto.NoResultsError, fn -> Tags.get_message_tag!(message_tag.id) end
    end

    test "change_messages_tag/1 returns a tag changeset" do
      message_tag = Fixtures.message_tag_fixture()
      assert %Ecto.Changeset{} = Tags.change_message_tag(message_tag)
    end

    test "ensure that creating message_tag with same message and tag does not give an error" do
      message = Fixtures.message_fixture()
      tag = Fixtures.tag_fixture()
      Fixtures.message_tag_fixture(%{message_id: message.id, tag_id: tag.id})

      # we love upserts!
      assert {:ok, %MessageTag{}}
      Tags.create_message_tag(%{message_id: message.id, tag_id: tag.id})
    end
  end

  describe "contacts_tags" do
    test "list_contacts_tags/0 returns all contact_tags" do
      contact_tag = Fixtures.contact_tag_fixture()
      assert Tags.list_contacts_tags() == [contact_tag]
    end

    test "get_contacts_tag!/1 returns the contacts_tag with given id" do
      contact_tag = Fixtures.contact_tag_fixture()
      assert Tags.get_contact_tag!(contact_tag.id) == contact_tag
    end

    test "create_contacts_tag/1 with valid data creates a tag" do
      contact = Fixtures.contact_fixture()
      tag = Fixtures.tag_fixture()
      contact_tag = Fixtures.contact_tag_fixture(%{contact_id: contact.id, tag_id: tag.id})
      assert contact_tag.contact_id == contact.id
      assert contact_tag.tag_id == tag.id
    end

    test "update_contacts_tag/2 with valid data updates the tag" do
      contact = Fixtures.contact_fixture()
      contact_tag = Fixtures.contact_tag_fixture()

      assert {:ok, %ContactTag{} = contact_tag} =
               Tags.update_contact_tag(contact_tag, %{contact_id: contact.id})

      assert contact_tag.contact_id == contact.id
    end

    test "delete_contacts_tag/1 deletes the tag" do
      contact_tag = Fixtures.contact_tag_fixture()
      assert {:ok, %ContactTag{}} = Tags.delete_contact_tag(contact_tag)
      assert_raise Ecto.NoResultsError, fn -> Tags.get_contact_tag!(contact_tag.id) end
    end

    test "change_contacts_tag/1 returns a tag changeset" do
      contact_tag = Fixtures.contact_tag_fixture()
      assert %Ecto.Changeset{} = Tags.change_contact_tag(contact_tag)
    end

    test "ensure that creating contact_tag with same contact and tag give an error" do
      contact = Fixtures.contact_fixture()
      tag = Fixtures.tag_fixture()
      Fixtures.contact_tag_fixture(%{contact_id: contact.id, tag_id: tag.id})

      assert {:error, %Ecto.Changeset{}} =
               Tags.create_contact_tag(%{contact_id: contact.id, tag_id: tag.id})
    end

    test "remove_tag_from_all_message/2 removes teh tag and return the message ids " do
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

      {:ok, tag} = Repo.fetch_by(Tag, %{shortcode: "unread"})

      {:ok, message1_tag} = Tags.create_message_tag(%{message_id: message_1.id, tag_id: tag.id})
      {:ok, message2_tag} = Tags.create_message_tag(%{message_id: message_2.id, tag_id: tag.id})
      {:ok, message3_tag} = Tags.create_message_tag(%{message_id: message_3.id, tag_id: tag.id})

      untag_message_id = Tags.remove_tag_from_all_message(message_1.contact_id, "unread")

      assert message_1.id in untag_message_id
      assert message_2.id in untag_message_id
      assert message_3.id in untag_message_id

      assert_raise Ecto.NoResultsError, fn -> Tags.get_message_tag!(message1_tag.id) end
      assert_raise Ecto.NoResultsError, fn -> Tags.get_message_tag!(message2_tag.id) end
      assert_raise Ecto.NoResultsError, fn -> Tags.get_message_tag!(message3_tag.id) end
    end
  end
end
