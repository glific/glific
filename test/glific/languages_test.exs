defmodule Glific.LanguagesTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Settings
  }

  describe "languages" do
    test "list_languages/1 with language filtered",
         %{organization_id: _organization_id} = attrs do
      language1 = Fixtures.language_fixture(attrs)
      language2 = Fixtures.language_fixture(Map.merge(%{localized: true}, attrs))

      languages =
        Settings.list_languages(%{
          filter: %{localized: true}
        })

      assert language2 in languages

      non_localized_languages =
        Settings.list_languages(%{
          filter: %{localized: false}
        })

      assert language1 in non_localized_languages
    end
  end
end
