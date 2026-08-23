defmodule Glific.AI.Test.FixtureLargeTool do
  @moduledoc """
  A `Glific.AI.Tool` whose result blows past a deliberately small `max_result_bytes/0`, used to
  exercise `Glific.AI.Tool.Runner`'s size-cap truncation path.
  """

  use Glific.AI.Tool

  alias Glific.AI.Tool.Context

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "fixture_large_tool"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description, do: "A fixture tool that returns an oversized result. Used only in tests."

  @doc false
  @spec parameters() :: keyword()
  @impl true
  def parameters, do: []

  @doc false
  @spec max_result_bytes() :: pos_integer()
  @impl true
  def max_result_bytes, do: 300

  @doc false
  @spec run(map(), Context.t()) :: {:ok, term()} | {:error, String.t()}
  @impl true
  def run(_args, %Context{}) do
    rows = Enum.map(1..200, &%{id: &1, name: "item number #{&1}"})
    {:ok, rows}
  end
end
