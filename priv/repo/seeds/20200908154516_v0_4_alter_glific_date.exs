defmodule Glific.Repo.Seeds.V04AlterGlificData do
  use Glific.Seeds.Seed
  import Ecto.Changeset, only: [change: 2]

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners.Provider,
    Repo,
    Settings
  }

  def up(_repo) do
    [en_us | _] = Settings.list_languages(%{filter: %{label: "english"}})

    queries = [
      "UPDATE organizations SET provider_limit = 60, active_language_ids = '{#{en_us.id}}';",
      "UPDATE providers SET handler = 'Glific.Providers.Gupshup.Message', worker = 'Glific.Providers.Gupshup.Worker'"
    ]

    Enum.each(
      queries,
      &Repo.query(&1)
    )

    # add glifproxy as a channel also
    Repo.insert!(%Provider{
      name: "Glifproxy",
      url: "https://glific.io/",
      api_end_point: "http://glific.test:4000",
      handler: "Glific.Providers.Gupshup.Message",
      worker: "Glific.Providers.Glifproxy.Worker"
    })
  end
end
