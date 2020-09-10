defmodule Glific.Repo.Seeds.V04AlterGlificData do
  use Glific.Seeds.Seed
  import Ecto.Changeset, only: [change: 2]

  envs([:dev, :test, :prod])

  alias Glific.Repo

  def up(_repo) do
    Repo.query("UPDATE organizations SET provider_limit = 60;")
  end
end
