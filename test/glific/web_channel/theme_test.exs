defmodule Glific.WebChannel.ThemeTest do
  use Glific.DataCase, async: true

  alias Glific.Partners.Organization
  alias Glific.WebChannel.Theme

  defp organization(keys),
    do: %Organization{name: "NGO Name", services: %{"web" => %{keys: keys, secrets: %{}}}}

  describe "themes/0" do
    test "every theme has an id and a label the Settings dropdown can render" do
      for theme <- Theme.themes() do
        assert is_binary(theme.id) and theme.id != ""
        assert is_binary(theme.label) and theme.label != ""
      end
    end

    test "ids are unique, so a choice resolves to exactly one palette" do
      ids = Enum.map(Theme.themes(), & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "the default is one of the offered themes" do
      assert Enum.any?(Theme.themes(), &(&1.id == Theme.default_theme()))
    end
  end

  describe "for_organization/1" do
    test "reads the organization's branding off its web credential" do
      theme =
        organization(%{
          "theme" => "violet",
          "logo_url" => "https://cdn.example.org/logo.svg",
          "display_name" => "Example NGO"
        })
        |> Theme.for_organization()

      assert theme == %{
               theme: "violet",
               logo_url: "https://cdn.example.org/logo.svg",
               display_name: "Example NGO"
             }
    end

    test "every offered theme survives a round trip" do
      for %{id: id} <- Theme.themes() do
        assert %{theme: ^id} = Theme.for_organization(organization(%{"theme" => id}))
      end
    end

    test "falls back to the organization name when there is no credential" do
      theme = Theme.for_organization(%Organization{name: "NGO Name", services: %{}})

      assert theme == %{theme: Theme.default_theme(), logo_url: nil, display_name: "NGO Name"}
    end

    test "falls back to the organization name when the display name is blank" do
      assert %{display_name: "NGO Name"} =
               Theme.for_organization(organization(%{"display_name" => "   "}))
    end

    test "falls back to the default theme when the name is not one we offer" do
      for name <- ["chartreuse", "#ffe600", "", nil, 42] do
        assert %{theme: "zinc"} = Theme.for_organization(organization(%{"theme" => name}))
      end
    end

    test "accepts a theme name whatever its casing or padding" do
      assert %{theme: "violet"} =
               Theme.for_organization(organization(%{"theme" => "  Violet  "}))
    end

    test "drops a logo url that is not served over https" do
      for url <- ["http://cdn.example.org/logo.svg", "javascript:alert(1)", "logo.svg", nil] do
        assert %{logo_url: nil} = Theme.for_organization(organization(%{"logo_url" => url}))
      end
    end

    test "trims surrounding whitespace before validating" do
      theme =
        organization(%{"logo_url" => "  https://cdn.example.org/logo.svg  "})
        |> Theme.for_organization()

      assert theme.logo_url == "https://cdn.example.org/logo.svg"
    end
  end
end
