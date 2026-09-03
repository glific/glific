defmodule Glific.WebChannel.BrandingTest do
  use Glific.DataCase, async: true

  alias Glific.Partners.Organization
  alias Glific.WebChannel.Branding

  defp organization(keys),
    do: %Organization{name: "NGO Name", services: %{"web_channel" => %{keys: keys, secrets: %{}}}}

  describe "themes/0" do
    test "every theme has an id and a label the Settings dropdown can render" do
      for theme <- Branding.themes() do
        assert is_binary(theme.id) and theme.id != ""
        assert is_binary(theme.label) and theme.label != ""
      end
    end

    test "ids are unique, so a choice resolves to exactly one palette" do
      ids = Enum.map(Branding.themes(), & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "the default is one of the offered themes" do
      assert Enum.any?(Branding.themes(), &(&1.id == Branding.default_theme()))
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
        |> Branding.for_organization()

      assert theme == %{
               theme: "violet",
               logo_url: "https://cdn.example.org/logo.svg",
               display_name: "Example NGO"
             }
    end

    test "every offered theme survives a round trip" do
      for %{id: id} <- Branding.themes() do
        assert %{theme: ^id} = Branding.for_organization(organization(%{"theme" => id}))
      end
    end

    test "falls back to the organization name when there is no credential" do
      theme = Branding.for_organization(%Organization{name: "NGO Name", services: %{}})

      assert theme == %{theme: Branding.default_theme(), logo_url: nil, display_name: "NGO Name"}
    end

    test "falls back to the organization name when the display name is blank" do
      assert %{display_name: "NGO Name"} =
               Branding.for_organization(organization(%{"display_name" => "   "}))
    end

    test "falls back to the default theme when the name is not one we offer" do
      for name <- ["chartreuse", "#ffe600", "", nil, 42] do
        assert %{theme: "zinc"} = Branding.for_organization(organization(%{"theme" => name}))
      end
    end

    test "accepts a theme name whatever its casing or padding" do
      assert %{theme: "violet"} =
               Branding.for_organization(organization(%{"theme" => "  Violet  "}))
    end

    test "drops a logo url that is not served over https" do
      for url <- ["http://cdn.example.org/logo.svg", "javascript:alert(1)", "logo.svg", nil] do
        assert %{logo_url: nil} = Branding.for_organization(organization(%{"logo_url" => url}))
      end
    end

    test "trims surrounding whitespace before validating" do
      theme =
        organization(%{"logo_url" => "  https://cdn.example.org/logo.svg  "})
        |> Branding.for_organization()

      assert theme.logo_url == "https://cdn.example.org/logo.svg"
    end
  end
end
