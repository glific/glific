defmodule Glific.WebChannel.Branding do
  @moduledoc """
  Per-organisation branding for the web channel — its colours, logo, display name and the
  business profile contacts can open from the chat menu.

  One deployment serves every organisation and the widget is a single build, so branding is
  read at runtime from the organisation's `web_channel` credential rather than baked in. An
  organisation that has not filled the credential in yet still gets a usable surface built
  from its own name and the default palette.

  An organisation picks its own two colours. Only `primary` is ever painted behind text, and
  the text colour over it is computed here rather than chosen by the admin — which is what
  keeps an organisation from producing an unreadable widget. `secondary` is decorative and
  never carries text, so it needs no such guarantee.
  """

  alias Glific.Partners.Organization

  @provider_code "web_channel"

  # Glific's own green and amber, so an organisation that has set nothing still looks deliberate
  # rather than unstyled. Kept in step with FALLBACK_BRANDING in the widget's branding.ts, which
  # is what a 404 or an empty payload falls back to there.
  @default_primary "#119656"
  @default_secondary "#eab308"

  # The two neutrals the widget's own palette is built from, so a computed foreground looks
  # like the rest of the surface rather than like pure #000/#fff dropped on top of it.
  @on_dark "#fafafa"
  @on_light "#18181b"

  @about_fields ~w(description address website email hours)a

  @type about() :: %{
          description: String.t() | nil,
          address: String.t() | nil,
          website: String.t() | nil,
          email: String.t() | nil,
          hours: String.t() | nil
        }

  @type t() :: %{
          display_name: String.t(),
          logo_url: String.t() | nil,
          primary_color: String.t(),
          primary_foreground: String.t(),
          secondary_color: String.t(),
          about: about()
        }

  @doc """
  The primary colour an organisation gets before it has chosen one.
  """
  @spec default_primary() :: String.t()
  def default_primary, do: @default_primary

  @doc """
  The secondary colour an organisation gets before it has chosen one.
  """
  @spec default_secondary() :: String.t()
  def default_secondary, do: @default_secondary

  @doc """
  The branding an organisation's web channel should render with.
  """
  @spec for_organization(Organization.t()) :: t()
  def for_organization(organization) do
    keys = branding_keys(organization)
    primary = color(keys["primary_color"], @default_primary)

    %{
      display_name: display_name(keys["display_name"], organization),
      logo_url: logo_url(keys["logo_url"]),
      primary_color: primary,
      primary_foreground: readable_on(primary),
      secondary_color: color(keys["secondary_color"], @default_secondary),
      about: about(keys)
    }
  end

  @doc """
  The text colour to use over `hex`, whichever of the two neutrals contrasts with it more.

  Public because this is the guarantee the Settings page makes to an admin in words — that
  header text flips to stay legible — and a guarantee stated in one place and implemented in
  another is one that drifts.
  """
  @spec readable_on(String.t()) :: String.t()
  def readable_on(hex) do
    luminance = hex |> color(@default_primary) |> relative_luminance()

    if contrast(luminance, relative_luminance(@on_light)) >=
         contrast(luminance, relative_luminance(@on_dark)),
       do: @on_light,
       else: @on_dark
  end

  @spec branding_keys(Organization.t()) :: map()
  defp branding_keys(organization) do
    case organization.services[@provider_code] do
      %{keys: keys} when is_map(keys) -> keys
      _no_credential -> %{}
    end
  end

  @spec about(map()) :: about()
  defp about(keys),
    do: Map.new(@about_fields, &{&1, about_value(&1, keys["about_#{&1}"])})

  @spec about_value(atom(), term()) :: String.t() | nil
  defp about_value(:website, value), do: value |> trimmed() |> with_scheme()
  defp about_value(_field, value), do: trimmed(value)

  @spec trimmed(term()) :: String.t() | nil
  defp trimmed(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trimmed(_value), do: nil

  # An admin types "example.org"; the widget renders it as a link, and a href without a scheme
  # resolves against the widget's own host.
  @spec with_scheme(String.t() | nil) :: String.t() | nil
  defp with_scheme(nil), do: nil

  defp with_scheme(url) do
    if String.match?(url, ~r{^[a-z][a-z0-9+.-]*://}i), do: url, else: "https://#{url}"
  end

  @spec color(term(), String.t()) :: String.t()
  defp color(value, fallback) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      <<?#, r::binary-size(1), g::binary-size(1), b::binary-size(1)>> ->
        color("##{r}#{r}#{g}#{g}#{b}#{b}", fallback)

      <<?#, _rest::binary-size(6)>> = hex ->
        if hex =~ ~r/^#[0-9a-f]{6}$/, do: hex, else: fallback

      _malformed ->
        fallback
    end
  end

  defp color(_value, fallback), do: fallback

  @spec logo_url(term()) :: String.t() | nil
  defp logo_url(url) when is_binary(url) do
    url = String.trim(url)
    if String.starts_with?(url, "https://"), do: url
  end

  defp logo_url(_url), do: nil

  @spec display_name(term(), Organization.t()) :: String.t()
  defp display_name(name, organization) when is_binary(name) do
    case String.trim(name) do
      "" -> organization.name
      name -> name
    end
  end

  defp display_name(_name, organization), do: organization.name

  @spec contrast(float(), float()) :: float()
  defp contrast(first, second),
    do: (max(first, second) + 0.05) / (min(first, second) + 0.05)

  @spec relative_luminance(String.t()) :: float()
  defp relative_luminance(<<?#, r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    [r, g, b] = Enum.map([r, g, b], &channel/1)
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  @spec channel(String.t()) :: float()
  defp channel(hex) do
    value = String.to_integer(hex, 16) / 255
    if value <= 0.03928, do: value / 12.92, else: :math.pow((value + 0.055) / 1.055, 2.4)
  end
end
