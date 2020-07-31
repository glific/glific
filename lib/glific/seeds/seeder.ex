defmodule Glific.Seeds.Seeder do
  @moduledoc """
  Our first attempt at a deployment seeder script.
  Wish us luck
  """

  import Mix.PhilColumns

  @app :glific

  @doc false
  @spec seed(any, any) :: any
  def seed(opts \\ Keyword.new(), seeder \\ &PhilColumns.Seeder.run/4) do
    repos = load_repos() |> List.wrap()

    # set env with current_env/0 overwriting provided arg
    opts = Keyword.put(opts, :env, current_env())

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

    Enum.each(repos, fn repo ->
      seeder.(repo, seeds_path(repo), :up, opts)
    end)
  end

  defp current_env, do: :prod

  # Get active repo context
  @spec load_repos() :: any()
  defp load_repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
