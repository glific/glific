defmodule Glific.Seeds.Seed do
  @moduledoc """
  First experiments with PhilColumns. Hopefully it will work
  """
  defmacro __using__(_opts) do
    quote do
      use PhilColumns.Seed
    end
  end
end
