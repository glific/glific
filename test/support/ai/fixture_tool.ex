defmodule Glific.AI.Test.FixtureTool do
  @moduledoc """
  A minimal `Glific.AI.Tool` implementation used to exercise the `Tool` behaviour, the `use`
  macro defaults, and `Glific.AI.Tool.Context` outside of any real tool.
  """

  use Glific.AI.Tool

  alias Glific.AI.Tool.Context

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "fixture_tool"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description, do: "A fixture tool used only in tests."

  @doc false
  @spec parameters() :: keyword()
  @impl true
  def parameters, do: [query: [type: :string, required: true, doc: "What to look up."]]

  @doc false
  @spec run(map(), Context.t()) :: {:ok, term()} | {:error, String.t()}
  @impl true
  def run(%{"query" => query}, %Context{} = context) do
    {:ok, %{query: query, organization_id: context.organization_id}}
  end

  def run(_args, %Context{}), do: {:error, "query is required"}
end
