defmodule Glific.AI.Tool.Registry do
  @moduledoc """
  Maps a tool's `name/0` to the module implementing `Glific.AI.Tool` for it.

  `@tools` is an explicit list, not runtime module scanning — same rationale as
  `Glific.AI.Skill.Registry`.
  """

  alias Glific.AI.Tools.{DescribeTable, QueryOrgData}

  @tools [DescribeTable, QueryOrgData]

  @by_name Map.new(@tools, &{&1.name(), &1})

  @doc "Looks up the module registered under `name`."
  @spec fetch(String.t()) :: {:ok, module()} | {:error, :unknown_tool}
  def fetch(name) when is_binary(name) do
    case Map.fetch(@by_name, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_tool}
    end
  end

  @doc "Every registered tool module."
  @spec all() :: [module()]
  def all, do: @tools

  @doc "Every registered tool name."
  @spec names() :: [String.t()]
  def names, do: Map.keys(@by_name)
end
