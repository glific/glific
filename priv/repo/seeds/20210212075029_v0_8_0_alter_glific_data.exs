defmodule Glific.Repo.Seeds.AddGlificData_v0_8_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners.Provider,
    Partners.Credential,
    Repo
  }

  def up(_repo) do
    adding_simulators()
  end

  defp adding_simulators() do
  end
end
