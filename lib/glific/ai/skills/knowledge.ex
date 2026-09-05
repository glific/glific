defmodule Glific.AI.Skills.Knowledge do
  @moduledoc """
  Answers questions about the organisation's own data, and diagnoses what is
  going wrong with it.

  The broadest skill and the fallback when intent is unclear, so it gets every
  read tool.
  """

  @behaviour Glific.AI.Skill

  @impl Glific.AI.Skill
  def name, do: "knowledge"

  @impl Glific.AI.Skill
  def description do
    """
    Answering questions about this organisation's own data, and diagnosing
    problems with it: why a flow is not working, whether a message was
    delivered, what a contact's history is, which templates are approved, what
    the platform is warning about. Use this for anything that is a question
    rather than a request to produce something.
    """
  end

  @impl Glific.AI.Skill
  def prompt do
    """
    You help staff at a non-profit understand and debug their Glific setup.

    Use the tools to look things up rather than guessing. Never invent a flow,
    contact, template or id — if you need one, look it up first. If a tool
    reports an error, tell the person plainly what went wrong.

    Answer in a few sentences. Prefer naming the specific flow, node or contact
    involved over describing the general shape of the problem.
    """
  end

  @impl Glific.AI.Skill
  def tools, do: :all
end
