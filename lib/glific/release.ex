defmodule Glific.Release do
  @moduledoc """
    This file will be handling production database migrations
    Called from "build_scripts/entrypoint.sh" just before starting up application
  """

  @app :glific

  @doc """
    We will use this to initate the migration on production
  """
  @spec migrate() :: any()
  def migrate do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
    As name suggest, we will use it for rollback
  """
  @spec rollback(any(), any()) :: any()
  def rollback(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # Get active repo context
  @spec repos() :: any()
  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
