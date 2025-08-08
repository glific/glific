defmodule Glific.Seeds.Seeds20250721231205AddAiPlatformProvider do
  use Glific.Seeds.Seed

  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  tags([:kaapi])

  def up(_repo, _opts) do
    add_kaapi()
  end

  def down(_repo, _opts) do
    from(p in Provider, where: p.shortcode == "kaapi")
    |> Repo.delete_all()
  end

  @spec add_kaapi() :: any()
  defp add_kaapi() do
    query = from(p in Provider, where: p.shortcode == "kaapi")

    # add only if does not exist
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Kaapi",
          shortcode: "kaapi",
          description:
            "AI platform to handle OpenAI-based operations and integrations in Glific.",
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
