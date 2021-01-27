defmodule MyApp.Repo.Migrations.UpdateObanJobsToV10 do
  use Ecto.Migration

  defdelegate up, to: Oban.Migrations
  defdelegate down, to: Oban.Migrations
end
