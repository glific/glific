defmodule Glific.WebChannel.BrandingTest do
  @moduledoc false

  use Glific.DataCase, async: true

  alias Glific.Partners.Organization
  alias Glific.WebChannel.Branding

  defp organization(keys),
    do: %Organization{name: "NGO Name", services: %{"web_channel" => %{keys: keys, secrets: %{}}}}

  describe "readable_on/1" do
    test "flips to dark text on a light primary and light text on a dark one" do
      assert Branding.readable_on("#ffffff") == Branding.readable_on("#ffb900")
      refute Branding.readable_on("#ffffff") == Branding.readable_on("#18181b")
    end

    test "clears WCAG AA against the colour it was chosen for" do
      for primary <- ["#ffffff", "#000000", "#119656", "#eab308", "#ff6900", "#4c3bcf"] do
        assert contrast(primary, Branding.readable_on(primary)) >= 4.5,
               "#{primary} is unreadable under #{Branding.readable_on(primary)}"
      end
    end

    test "falls back rather than raising on a colour it cannot parse" do
      assert Branding.readable_on("not a colour") ==
               Branding.readable_on(Branding.default_primary())
    end
  end

  describe "for_organization/1" do
    test "reads the organization's branding off its web channel credential" do
      branding =
        organization(%{
          "display_name" => "Example NGO",
          "logo_url" => "https://cdn.example.org/logo.png",
          "primary_color" => "#4C3BCF",
          "secondary_color" => "#FF8A3D",
          "about_description" => "We run skill-building journeys.",
          "about_address" => "Mumbai, Maharashtra",
          "about_website" => "example.org",
          "about_email" => "support@example.org",
          "about_hours" => "Mon-Sat, 9am-7pm IST"
        })
        |> Branding.for_organization()

      assert branding == %{
               display_name: "Example NGO",
               logo_url: "https://cdn.example.org/logo.png",
               primary_color: "#4c3bcf",
               primary_foreground: Branding.readable_on("#4c3bcf"),
               secondary_color: "#ff8a3d",
               about: %{
                 description: "We run skill-building journeys.",
                 address: "Mumbai, Maharashtra",
                 website: "https://example.org",
                 email: "support@example.org",
                 hours: "Mon-Sat, 9am-7pm IST"
               }
             }
    end

    test "falls back to the organization's own name and the default palette" do
      branding = %{} |> organization() |> Branding.for_organization()

      assert branding.display_name == "NGO Name"
      assert branding.logo_url == nil
      assert branding.primary_color == Branding.default_primary()
      assert branding.secondary_color == Branding.default_secondary()

      assert branding.about == %{
               description: nil,
               address: nil,
               website: nil,
               email: nil,
               hours: nil
             }
    end

    test "falls back when the organization has no web channel credential at all" do
      branding = %Organization{name: "NGO Name", services: %{}} |> Branding.for_organization()

      assert branding.display_name == "NGO Name"
      assert branding.primary_color == Branding.default_primary()
    end

    test "expands a three digit colour and ignores one it cannot parse" do
      branding =
        organization(%{"primary_color" => "#ABC", "secondary_color" => "rebeccapurple"})
        |> Branding.for_organization()

      assert branding.primary_color == "#aabbcc"
      assert branding.secondary_color == Branding.default_secondary()
    end

    test "treats whitespace-only values as unset" do
      branding =
        organization(%{"display_name" => "   ", "about_address" => "  "})
        |> Branding.for_organization()

      assert branding.display_name == "NGO Name"
      assert branding.about.address == nil
    end

    test "leaves a website that already carries a scheme alone" do
      branding =
        organization(%{"about_website" => "http://example.org/about"})
        |> Branding.for_organization()

      assert branding.about.website == "http://example.org/about"
    end

    test "refuses a logo that is not served over https" do
      branding =
        organization(%{"logo_url" => "http://cdn.example.org/logo.png"})
        |> Branding.for_organization()

      assert branding.logo_url == nil
    end
  end

  @spec contrast(String.t(), String.t()) :: float()
  defp contrast(first, second) do
    [first, second] = Enum.map([first, second], &luminance/1)
    (max(first, second) + 0.05) / (min(first, second) + 0.05)
  end

  @spec luminance(String.t()) :: float()
  defp luminance(<<?#, r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    [r, g, b] =
      Enum.map([r, g, b], fn hex ->
        value = String.to_integer(hex, 16) / 255
        if value <= 0.03928, do: value / 12.92, else: :math.pow((value + 0.055) / 1.055, 2.4)
      end)

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
end
