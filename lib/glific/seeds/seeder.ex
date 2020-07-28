defmodule Glific.Seeds.Seeder do
  @moduledoc """
  Our first attempt at a deployment seeder script.
  Wish us luck
  """

  import Mix.Ecto
  import Mix.PhilColumns

  @doc false
  @spec seed(any, any) :: any
  def seed(opts, seeder \\ &PhilColumns.Seeder.run/4) do
    repos = parse_repo(opts) |> List.wrap()

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
end
