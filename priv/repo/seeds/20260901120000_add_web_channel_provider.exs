defmodule Glific.Repo.Seeds.AddWebChannelProvider do
  use Glific.Seeds.Seed

  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo,
    WebChannel.Theme
  }

  envs([:dev, :test, :prod])

  tags([:web_channel])

  def up(_repo, _opts) do
    add_web_channel_provider()
  end

  @spec add_web_channel_provider() :: any()
  defp add_web_channel_provider() do
    query = from(p in Provider, where: p.shortcode == "web")

    # add only if does not exist
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Web Channel",
          shortcode: "web",
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
              type: :string,
              label: "Logo URL (https)",
              default: nil,
              view_only: false,
              position: 2
            },
            theme: %{
              type: :select,
              label: "Theme",
              default: Theme.default_theme(),
              view_only: false,
              position: 3,
              options: Theme.themes()
            }
          },
          secrets: %{}
        })
  end
end
