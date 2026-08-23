defmodule Glific.AI.Skills.Echo do
  @moduledoc """
  Reference skill: asks the model to repeat the given `message` back verbatim.

  No tools, a trivial deterministic system prompt, structured output, or gating. It exists
  purely as the end-to-end smoke test for the agent runtime — if `Echo` can run a step and
  return an answer, the runtime's wiring (registry lookup, actor context, model call,
  message persistence) works.
  """

  use Glific.AI.Skill

  @doc "Returns \"echo\"."
  @spec name() :: String.t()
  @impl true
  def name, do: "echo"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description, do: "Repeats the given message back verbatim. Smoke-tests the agent runtime."

  @doc false
  @spec model() :: String.t()
  @impl true
  def model, do: "anthropic:claude-sonnet-5"

  @doc false
  @spec system_prompt(map()) :: String.t()
  @impl true
  def system_prompt(%{"message" => message}) do
    "Repeat the following message back to the user, verbatim and with nothing added:\n\n" <>
      message
  end

  @doc false
  @spec output_schema() :: nil
  @impl true
  def output_schema, do: nil

  @doc false
  @spec validate_input(map()) :: {:ok, map()} | {:error, String.t()}
  @impl true
  def validate_input(%{"message" => message} = input) when is_binary(message) and message != "",
    do: {:ok, input}

  def validate_input(_input), do: {:error, "message is required"}
end
