defmodule Glific.AI.Test.FixtureSlowTool do
  @moduledoc """
  A `Glific.AI.Tool` that sleeps before answering, used to exercise
  `Glific.AI.Tool.Runner`'s timeout path without waiting out the real 15s budget — tests shrink
  the timeout via `Application.put_env(:glific, Glific.AI.Tool.Runner, timeout_ms: ...)` and rely
  on this tool sleeping longer than that shrunk value.
  """

  use Glific.AI.Tool

  alias Glific.AI.Tool.Context

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "fixture_slow_tool"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description, do: "A fixture tool that sleeps before answering. Used only in tests."

  @doc false
  @spec parameters() :: keyword()
  @impl true
  def parameters, do: [sleep_ms: [type: :pos_integer, required: true, doc: "How long to sleep."]]

  @doc false
  @spec run(map(), Context.t()) :: {:ok, term()} | {:error, String.t()}
  @impl true
  def run(%{"sleep_ms" => sleep_ms}, %Context{}) do
    Process.sleep(sleep_ms)
    {:ok, %{slept_ms: sleep_ms}}
  end

  def run(_args, %Context{}), do: {:error, "sleep_ms is required"}
end
