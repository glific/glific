defmodule Glific.Seeds.Seeder do
  @moduledoc """
  Our first attempt at a deployment seeder script.
  Wish us luck
  """

  @app :glific

  @doc false
  @spec seed(any, any) :: any
  def seed(opts \\ Keyword.new(), seeder \\ &PhilColumns.Seeder.run/4) do
    repos = load_repos()
    # set env with current_env/0 overwriting provided arg
    # Tags keyword is required for the PhilColumns library
    opts =
      Keyword.put(opts, :env, current_env())
      |> Keyword.put(:tags, [])

    opts =
      if opts[:to] || opts[:step] || opts[:all],
        do: opts,
        else: Keyword.put(opts, :all, true)

    opts =
      if opts[:log],
        do: opts,
        else: Keyword.put(opts, :log, :info)

    opts =
      if opts[:quiet],
        do: Keyword.put(opts, :log, false),
        else: opts

    # We need to run the with the loaded repo. This is a public API provided
    for repo <- repos do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &run_seeders(&1, seeder, opts))
    end
  end

  defp current_env, do: :prod

  # Get active repo context
  @spec load_repos() :: any()
  defp load_repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end

  @spec run_seeders(any(), any(), Keyword.t()) :: any()
  defp run_seeders(repo, seeder, opts) do
    seeder.(repo, Path.join(:code.priv_dir(@app), "repo/seeds"), :up, opts)
  end
end
