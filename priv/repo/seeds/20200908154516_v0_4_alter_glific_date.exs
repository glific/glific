defmodule Glific.Repo.Seeds.V04AlterGlificData do
  use Glific.Seeds.Seed
  import Ecto.Changeset, only: [change: 2]

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners.Provider,
    Repo
  }

  def up(_repo) do
    queries = [
      "UPDATE organizations SET provider_limit = 60;",
      "UPDATE providers SET handler = 'Glific.Providers.Gupshup.Message', worker = 'Glific.Providers.Gupshup.Worker'"
    ]

    Enum.each(
      queries,
      &Repo.query(&1)
    )

    # add glifproxy as a channel also
    Repo.insert!(%Provider{
      name: "GlifProxy",
      url: "https://glific.io/",
      api_end_point: "https://glific.test:4000/",
      handler: "Glific.Providers.Gupshup.Message",
      worker: "Glific.Providers.GlifProxy.Worker"
    })
  end
end
