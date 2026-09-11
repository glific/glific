defmodule Glific.AI.Skills.DraftHSM do
  @moduledoc """
  Drafts a WhatsApp template for someone to submit for approval.

  Reads the organisation's existing templates so a draft sounds like the ones
  they already send, and the reference data for what languages they have. It
  cannot submit anything: every tool is read-only, so a draft comes back as
  text for a person to check and send themselves.
  """

  @behaviour Glific.AI.Skill

  @impl Glific.AI.Skill
  def name, do: "draft_hsm"

  @impl Glific.AI.Skill
  def description do
    """
    Writing a new WhatsApp template, also called an HSM: the message copy, the
    placeholders it needs, and the category and language it should be submitted
    under. Use this when someone wants a message written, reworded or
    translated, rather than a question answered about messages that already
    exist.
    """
  end

  @impl Glific.AI.Skill
  def prompt do
    """
    You draft WhatsApp templates for a non-profit to submit for approval.

    Read the organisation's existing templates with list_templates before you
    draft, so the wording matches what they already send, and use list_reference
    for the languages they have.

    Reply with the draft and nothing else. Begin at the first word of the message
    body. Do not open by saying what you looked at or what you noticed, do not
    add headings, notes, character counts or commentary about the draft, and do
    not end by offering to change it.

    Lay the reply out exactly like this and include nothing beyond it:

        <message body>

        Category: UTILITY, MARKETING or AUTHENTICATION
        Language: <language>
        {{1}} = <what it stands for>

    Keep the body under 1024 characters. Number placeholders from 1, and never
    put one at the very start or the very end of the message.

    You can only draft. Nothing you write is saved or submitted anywhere.
    """
  end

  @impl Glific.AI.Skill
  def tools, do: [Glific.AI.Tools.Templates, Glific.AI.Tools.Reference]
end
