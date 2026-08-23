defmodule Glific.AI.Test.FixtureSkill do
  @moduledoc """
  A `Glific.AI.Skill` implementation that overrides every default and implements both
  optional gating callbacks, used to exercise the parts of the behaviour `Glific.AI.Skills.Echo`
  leaves at their defaults.
  """

  use Glific.AI.Skill

  alias Glific.AI.Test.FixtureTool

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "fixture_skill"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description, do: "A fixture skill used only in tests."

  @doc false
  @spec provider() :: atom()
  @impl true
  def provider, do: :google

  @doc false
  @spec model() :: String.t()
  @impl true
  def model, do: "google:gemini-2.5-pro"

  @doc false
  @spec system_prompt(map()) :: String.t()
  @impl true
  def system_prompt(%{"topic" => topic}), do: "You are a fixture assistant about #{topic}."

  @doc false
  @spec initial_messages(map()) :: [ReqLLM.Message.t()]
  @impl true
  def initial_messages(%{"topic" => topic}) do
    [ReqLLM.Context.user("Let's talk about #{topic}.")]
  end

  @doc false
  @spec tools() :: [module()]
  @impl true
  def tools, do: [FixtureTool]

  @doc false
  @spec output_schema() :: keyword()
  @impl true
  def output_schema, do: [answer: [type: :string, required: true]]

  @doc false
  @spec validate_input(map()) :: {:ok, map()} | {:error, String.t()}
  @impl true
  def validate_input(%{"topic" => topic} = input) when is_binary(topic) and topic != "",
    do: {:ok, input}

  def validate_input(_input), do: {:error, "topic is required"}

  @doc false
  @spec max_steps() :: pos_integer()
  @impl true
  def max_steps, do: 3

  @doc false
  @spec gate_policy() :: Glific.AI.Skill.gate_policy()
  @impl true
  def gate_policy, do: {:on_final, 300}

  @doc false
  @spec build_proposal(term(), map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def build_proposal(result, %{"topic" => topic}), do: {:ok, %{topic: topic, result: result}}

  @doc false
  @spec on_decision(:accepted | :rejected, term(), map()) ::
          {:done, map()} | {:continue, [ReqLLM.Message.t()]}
  @impl true
  def on_decision(:accepted, _conversation, proposal), do: {:done, proposal}

  def on_decision(:rejected, _conversation, proposal),
    do: {:continue, [ReqLLM.Context.user("That proposal was rejected: #{inspect(proposal)}")]}

  @doc false
  @spec required_role() :: Glific.AI.Skill.role()
  @impl true
  def required_role, do: :manager

  @doc false
  @spec feature_flag() :: atom()
  @impl true
  def feature_flag, do: :ai_fixture_skill_enabled

  @doc false
  @spec stream_thinking?() :: boolean()
  @impl true
  def stream_thinking?, do: true

  @doc false
  @spec cache_ttl() :: String.t()
  @impl true
  def cache_ttl, do: "1h"
end
