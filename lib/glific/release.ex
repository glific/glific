# This file will be handling production database migrations
# Called from "build_scripts/entrypoint.sh" just before starting up application
defmodule Glific.Release do
    @app :glific
  
    def migrate do
      for repo <- repos() do
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      end
    end
  
    def rollback(repo, version) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    end
  
    defp repos do
      Application.load(@app)
      Application.fetch_env!(@app, :ecto_repos)
    end
  end