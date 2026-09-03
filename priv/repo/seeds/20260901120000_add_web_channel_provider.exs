defmodule Glific.Repo.Seeds.AddWebChannelProvider do
  @moduledoc """
  Seeds the `web_channel` provider, whose keys drive the branding form on the Settings page
  and the values the widget reads at boot.
  """

  use Glific.Seeds.Seed

  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo,
    WebChannel.Branding
  }

  envs([:dev, :test, :prod])

  tags([:web_channel])

  @doc """
  Adds the web channel provider, once.
  """
  @spec up(Ecto.Repo.t(), Keyword.t()) :: any()
  def up(_repo, _opts) do
    add_web_channel_provider()
  end

  @spec add_web_channel_provider() :: any()
  defp add_web_channel_provider() do
    query = from(p in Provider, where: p.shortcode == "web_channel")

    # add only if does not exist
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Web Channel",
          shortcode: "web_channel",
          description: "Branding shown to beneficiaries chatting from a browser",
          group: nil,
          is_required: false,
          # `position` drives field order on the Settings page; jsonb hands the keys back
          # sorted by length, which would otherwise put Theme first.
          keys: %{
            display_name: %{
              type: :string,
              label: "Display Name",
              default: nil,
              view_only: false,
              position: 1
            },
            logo_url: %{
              type: :upload,
              label: "Logo",
              default: nil,
              view_only: false,
              position: 2,
              max_size_kb: 200,
              accept: "image/png,image/jpeg,image/webp,image/svg+xml",
              helper_text: "PNG, JPEG, WEBP or SVG up to 200KB. Landscape works best."
            },
            theme: %{
              type: :select,
              label: "Theme",
              default: Branding.default_theme(),
              view_only: false,
              position: 3,
              options: Branding.themes()
            }
          },
          secrets: %{}
        })
  end
end
