defmodule Glific.RepoTest do
  use Glific.DataCase

  alias Glific.{
    Settings,
    Settings.Language
  }

  describe "repo" do
    @valid_attrs %{
      label: "English (United States)",
      locale: "en_US",
      is_active: true
    }

    @valid_hindi_attrs %{
      label: "Hindi (India)",
      locale: "hi_IN",
      is_active: true
    }

    def language_fixture(attrs \\ @valid_attrs) do
      {:ok, language} =
        attrs
        |> Enum.into(attrs)
        |> Settings.create_language()

      language
    end

    test "fetch returns the right language" do
      en = language_fixture()
      hi = language_fixture(@valid_hindi_attrs)

      assert {:ok, hi} == Repo.fetch(Language, hi.id)
      assert {:ok, en} == Repo.fetch(Language, en.id)
      assert :error == elem(Repo.fetch(Language, 123), 0)
    end

    test "fetch_by returns the right language" do
      en = language_fixture()
      hi = language_fixture(@valid_hindi_attrs)

      assert {:ok, hi} == Repo.fetch_by(Language, %{label: "Hindi (India)"})
      assert {:ok, en} == Repo.fetch_by(Language, %{locale: "en_US"})
      assert :error == elem(Repo.fetch_by(Language, %{locale: "does not exist"}), 0)
    end
  end
end
