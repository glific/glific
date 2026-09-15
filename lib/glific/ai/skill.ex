defmodule Glific.AI.Skill do
  @moduledoc """
  One thing Glific AI knows how to do.

  A skill is the unit the assistant routes to: answering a question about the
  organisation's data, drafting an HSM, reviewing a flow. It supplies the system
  prompt for that job and declares which tool areas it may read, so a skill sees
  only the tools its work needs rather than every tool in the platform.

  A skill can be reached two ways, and both end in the same place:

    * the person types a question and `Glific.AI.Router` classifies the intent
    * the UI invokes one directly — a "Draft HSM" button passes `skill:` and
      skips classification

  Adding a skill is a module plus one line in `Glific.AI.Skills`.
  """

  @doc """

  Identifier used in the API and recorded on the message row. Stable.

  """
  @callback name() :: String.t()

  @doc """
  What this skill is for, written so a model can choose between skills.

  This is the text the router classifies against, so it should describe the kind
  of request rather than the implementation.
  """
  @callback description() :: String.t()

  @doc """

  The system prompt for this skill.

  """
  @callback prompt() :: String.t()

  @doc """
  The tool modules this skill may read through, or `:all`.

  Narrowing matters: every tool a skill declares is a schema sent to the model
  on every turn, so a skill that needs templates should not also pay for flows.
  """
  @callback tools() :: [module()] | :all
end
