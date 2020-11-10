defmodule Glific.RepoTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Settings,
    Settings.Language
  }

  describe "repo" do
    @valid_attrs %{
      label: "Faker English (United States)",
      label_locale: "Faker English",
      locale: "faker_en_US",
      is_active: true
    }

    @valid_hindi_attrs %{
      label: "Faker Hindi (India)",
      label_locale: "Faker हिन्दी",
      locale: "faker_hi",
      is_active: true
    }

    def language_fixture(attrs \\ @valid_attrs) do
      {:ok, language} =
        attrs
        |> Enum.into(attrs)
        |> Settings.language_upsert()

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

      assert {:ok, hi} ==
               Repo.fetch_by(Language, %{label: "Faker Hindi (India)"})

      assert {:ok, en} ==
               Repo.fetch_by(Language, %{locale: "faker_en_US"})

      assert :error ==
               elem(
                 Repo.fetch_by(Language, %{locale: "does not exist"}),
                 0
               )
    end
  end
end
