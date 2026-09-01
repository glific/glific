defmodule Glific.WebChannel.Theme do
  @moduledoc """
  Per-organisation branding for the web channel.

  One deployment serves every organisation and the widget is a single build, so branding is
  read at runtime from the organisation's `web` credential rather than baked in. An
  organisation that has not filled the credential in yet still gets a usable theme built from
  its own name.

  An organisation picks a named theme rather than a colour of its own. The widget holds the
  matching palette, so the only thing that crosses this boundary is the name — which means an
  organisation cannot produce an unreadable widget, and contrast is settled once here rather
  than per organisation.
  """

  alias Glific.Partners.Organization

  @shortcode "web"

  # Kept in step with THEMES in glific-web-channel's src/services/themes.ts, which holds the
  # palette each of these names resolves to. A name the widget does not recognise falls back
  # there too, so the two lists drifting degrades rather than breaks.
  @themes [
    %{id: "violet", label: "Violet"},
    %{id: "blue", label: "Blue"},
    %{id: "green", label: "Green"},
    %{id: "teal", label: "Teal"},
    %{id: "rose", label: "Rose"},
    %{id: "orange", label: "Orange"},
    %{id: "amber", label: "Amber"},
    %{id: "zinc", label: "Zinc"}
  ]

  @default_theme "zinc"

  @type t() :: %{
          theme: String.t(),
          logo_url: String.t() | nil,
          display_name: String.t()
        }

  @doc """
  The themes an organisation may choose between, as the Settings dropdown renders them.
  """
  @spec themes() :: [%{id: String.t(), label: String.t()}]
  def themes, do: @themes

  @doc """
  The theme an organisation gets before it has chosen one.
  """
  @spec default_theme() :: String.t()
  def default_theme, do: @default_theme

  @doc """
  The branding an organisation's web channel should render with.
  """
  @spec for_organization(Organization.t()) :: t()
  def for_organization(organization) do
    keys = branding_keys(organization)

    %{
      theme: theme(keys["theme"]),
      logo_url: logo_url(keys["logo_url"]),
      display_name: display_name(keys["display_name"], organization)
    }
  end

  @spec branding_keys(Organization.t()) :: map()
  defp branding_keys(organization) do
    case organization.services[@shortcode] do
      %{keys: keys} when is_map(keys) -> keys
      _no_credential -> %{}
    end
  end

  @spec theme(term()) :: String.t()
  defp theme(name) when is_binary(name) do
    name = name |> String.trim() |> String.downcase()
    if Enum.any?(@themes, &(&1.id == name)), do: name, else: @default_theme
  end

  defp theme(_name), do: @default_theme

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
end
