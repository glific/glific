defmodule Glific.Seeds.Seeds20250721231205AddAiPlatformProvider do
  use Glific.Seeds.Seed

  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  tags([:ai_platform])

  def up(_repo, _opts) do
    add_ai_platform()
  end

  @spec add_ai_platform() :: any()
  defp add_ai_platform() do
    query = from(p in Provider, where: p.shortcode == "ai_platform")

    # add only if does not exist
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "AI Platform",
          shortcode: "ai_platform",
          description: "Handles OpenAI-based operations and integrations in Glific.",
          group: nil,
          is_required: false,
          keys: %{},
          secrets: %{
            api_key: %{
              type: :string,
              label: "API Key",
              default: nil,
              view_only: false
            }
          }
        })
  end
end
