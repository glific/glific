defmodule Glific.Release do
  @moduledoc """
  This file will be handling production database migrations. This is a standard elixir/ecto
  release file. Copied from:
  https://hexdocs.pm/phoenix/releases.html

  Called from "build_scripts/entrypoint.sh" just before starting up application
  """

  @app :glific

  @doc false
  @spec migrate() :: any()
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc false
  @spec rollback(any(), any()) :: any()
  def rollback(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp load_app do
    Application.load(@app)
  end

  # Get active repo context
  @spec repos() :: any()
  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
