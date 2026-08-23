defmodule Glific.AI.Skill.Registry do
  @moduledoc """
  Maps a skill's `name/0` to the module implementing `Glific.AI.Skill` for it.

  `@skills` is an explicit list, not runtime module scanning: explicit so Dialyzer can see
  every registered module, and so adding a skill is one reviewable line rather than a module
  quietly picked up by a naming convention.
  """

  alias Glific.AI.Skills.AskGlific
  alias Glific.AI.Skills.Echo
  alias Glific.AI.Skills.PromptGenerator
  alias Glific.AI.Skills.TemplateUtilityRewrite

  @skills [AskGlific, Echo, PromptGenerator, TemplateUtilityRewrite]

  @doc """
  Every registered skill module, including any supplied by `:ai_extra_skills`.

  Tests register fixture skills through that config key rather than being listed here directly:
  `test/support/` compiles after `lib/`, so a compile-time reference to a test module from this
  module fails to build.
  """
  @spec all() :: [module()]
  def all, do: @skills ++ Application.get_env(:glific, :ai_extra_skills, [])

  @doc "Looks up the module registered under `name`."
  @spec fetch(String.t()) :: {:ok, module()} | {:error, :unknown_skill}
  def fetch(name) when is_binary(name) do
    case Enum.find(all(), &(&1.name() == name)) do
      nil -> {:error, :unknown_skill}
      module -> {:ok, module}
    end
  end

  @doc "Every registered skill name."
  @spec names() :: [String.t()]
  def names, do: Enum.map(all(), & &1.name())
end
