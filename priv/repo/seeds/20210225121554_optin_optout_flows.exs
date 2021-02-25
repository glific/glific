defmodule Glific.Repo.Seeds.OptinOptoutFlows do
  use Glific.Seed

  envs([:dev])

  def up(_repo) do
    add_optin_flow()
  end

  defp add_optin_flow() do
  end
end
