defmodule Glific.Repo.Seeds.AddOpenAiProvider do
  use Glific.Seeds.Seed
  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  tags([:kaapi])

  def up(_repo, _opts) do
    query = from(p in Provider, where: p.shortcode == "openai")

    # add only if does not exist
    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "OpenAI",
          shortcode: "openai",
          description: "To bring AI capabilities to your bot using your own OpenAI keys",
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

  def down(_repo, _opts) do
    Provider
    |> where([p], p.shortcode == "openai")
    |> Repo.delete_all()
  end
end
