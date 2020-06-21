defmodule Glific.SettingsTest do
  use Glific.DataCase, async: false

  alias Glific.{
    Settings,
    Settings.Language
  }

  describe "languages" do
    @valid_attrs %{
      label: "English (United States)",
      label_locale: "English",
      locale: "en_US",
      is_active: true
    }

    @update_attrs %{
      description: "we now have a description",
      locale: "hi_IN",
      is_active: false
    }
    @invalid_attrs %{is_active: nil, label: 123, locale: nil}
    @invalid_more_attrs %{label: "Label with no Locale"}

    def language_fixture(attrs \\ %{}) do
      {:ok, language} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Settings.language_upsert()

      language
    end

    test "list_languages/0 returns all languages" do
      language = language_fixture()
      assert Settings.list_languages() == [language]

      assert Settings.list_languages(%{label: "English", locale: "en"}) == [language]
      assert Settings.list_languages(%{label: "English", locale: "hi"}) == []
    end

    test "count_languages/0 returns count of all languages" do
      _ = language_fixture()
      assert Settings.count_languages() == 1

      assert Settings.count_languages(%{filter: %{label: "English (United States)"}}) == 1
    end

    test "get_language!/1 returns the language with given id" do
      language = language_fixture()
      assert Settings.get_language!(language.id) == language
    end

    test "create_language/1 with valid data creates a language" do
      assert {:ok, %Language{} = language} = Settings.create_language(@valid_attrs)
      assert language.description == nil
      assert language.is_active == true
      assert language.label == "English (United States)"
      assert language.locale == "en_US"
    end

    test "create_language/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Settings.create_language(@invalid_attrs)
    end

    test "create_language/1 with more invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Settings.create_language(@invalid_more_attrs)
    end

    test "update_language/2 with valid data updates the language" do
      language = language_fixture()
      assert {:ok, %Language{} = language} = Settings.update_language(language, @update_attrs)
      assert language.description == "we now have a description"
      assert language.is_active == false
      assert language.locale == "hi_IN"
    end

    test "update_language/2 with invalid data returns error changeset" do
      language = language_fixture()
      assert {:error, %Ecto.Changeset{}} = Settings.update_language(language, @invalid_attrs)
      assert language == Settings.get_language!(language.id)
    end

    test "delete_language/1 deletes the language" do
      language = language_fixture()
      assert {:ok, %Language{}} = Settings.delete_language(language)
      assert_raise Ecto.NoResultsError, fn -> Settings.get_language!(language.id) end
    end

    test "change_language/1 returns a language changeset" do
      language = language_fixture()
      assert %Ecto.Changeset{} = Settings.change_language(language)
    end

    test "table constraint on languages with the same label and locale" do
      _language = language_fixture()
      assert {:error, %Ecto.Changeset{}} = Settings.create_language(@valid_attrs)
    end

    test "deleting a language with tags associated, should result in an error" do
      lang = Glific.Seeds.seed_language()
      Glific.Seeds.seed_tag(lang)

      assert {:error, %Ecto.Changeset{}} = Settings.delete_language(elem(lang, 0))
    end
  end
end
