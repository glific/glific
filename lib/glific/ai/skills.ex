defmodule Glific.AI.Skills do
  @moduledoc """
  The skills Glific AI can route to.

  Adding one is a module implementing `Glific.AI.Skill` plus a line in `@skills`.
  """

  alias Glific.AI.{Skill, Tools}

  @skills [
    Glific.AI.Skills.Knowledge,
    Glific.AI.Skills.DraftHSM
  ]

  @doc "Every available skill."
  @spec all() :: [module()]
  def all, do: @skills

  @doc """
  The skill used when intent is unclear.

  Answering from the organisation's own data is the safe fallback: it reads and
  never acts.
  """
  @spec default() :: module()
  def default, do: Glific.AI.Skills.Knowledge

  @doc "Looks a skill up by the name the API uses."
  @spec fetch(String.t() | nil) :: {:ok, module()} | {:error, String.t()}
  def fetch(name) when name in [nil, ""], do: {:ok, default()}

  def fetch(name) do
    case Enum.find(all(), &(&1.name() == name)) do
      nil -> {:error, ~s(There is no skill called "#{name}".)}
      skill -> {:ok, skill}
    end
  end

  @doc "The tools one skill may use, as the provider needs them."
  @spec tools(module()) :: [Glific.AI.Tool.spec()]
  def tools(skill) do
    case skill.tools() do
      :all -> Tools.all()
      modules -> Tools.all(modules)
    end
  end

  @doc """
  Every skill as `{name, description}`, for choosing between them.

  Also what an API can offer a UI so buttons are not hardcoded against this list.
  """
  @spec catalogue() :: [%{name: String.t(), description: String.t()}]
  def catalogue do
    Enum.map(all(), &%{name: &1.name(), description: &1.description()})
  end

  @doc false
  @spec behaviour() :: module()
  def behaviour, do: Skill
end
