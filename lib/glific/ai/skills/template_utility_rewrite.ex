defmodule Glific.AI.Skills.TemplateUtilityRewrite do
  @moduledoc """
  Rewrites a WhatsApp HSM draft's body so it is eligible for Meta's UTILITY template category,
  and explains what changed and why.

  No tools, one structured-output pass — `Glific.Templates.UtilityRewriter` is the only caller,
  driving this skill through `Glific.AI.Run.sync/3` from inside a live GraphQL mutation
  (`rewriteTemplateForUtility`). `UtilityRewriter` also owns every hard validation this skill's
  output must satisfy (variable preservation, the 1024-character budget, the category
  whitelist) and the bounded one-retry loop when a rewrite violates one of them — this module
  is purely the prompt and the schema.

  ## The input seam

  `Glific.AI.Runtime` derives a skill's `input` as `%{"message" => <first user message text>}`
  (see its moduledoc, "Deriving input") — there is no richer structured input available today.
  `Glific.Templates.UtilityRewriter.encode_draft/2` serialises the draft's label, body, footer
  and buttons into that single string, in a fixed `LABEL: / BODY: / FOOTER: / BUTTONS:` layout;
  `system_prompt/1` below documents that exact layout so the model can parse it. This is a
  deliberate seam, not a design choice worth defending: the day `input` grows past a single
  string, this encoding step is the first thing to delete.

  ## Determinism and caching

  `system_prompt/1` ignores `input` entirely and returns a fixed module attribute, so it is
  identical on every call — the whole prompt is a stable cache prefix. The draft itself (and,
  on a retry, the rejection reason) arrives as the conversation's ordinary first user message,
  not embedded in the system prompt, precisely so the large instructional prefix stays
  cacheable across every rewrite request from every organisation.
  """

  use Glific.AI.Skill

  alias Glific.AI.Skill

  @meta_prompt ~S"""
  You rewrite WhatsApp Business message templates so they qualify for Meta's UTILITY template
  category, for Glific — a WhatsApp platform used by non-profits across India to message the
  people they serve.

  ## UTILITY vs MARKETING

  Meta classifies every WhatsApp template into a category; the two that matter here are UTILITY
  and MARKETING. Getting this right matters: a template that reads like a utility message but is
  actually marketing gets rejected or later flagged, and a message that stays marketing when it
  didn't need to costs the sender more per message and needs an extra opt-in.

  A message is UTILITY when it facilitates, confirms, updates, or follows up on a specific
  transaction, request, application, appointment, or enrollment that the recipient already
  initiated or is already part of. Concretely, in Glific's own words: "Account updates, order
  confirmations, shipping notifications, alerts, and transactional messages."

  A message is MARKETING when it promotes something, invites the recipient into something new,
  or tries to re-engage someone who has gone quiet. In Glific's own words: "Promotional content,
  offers, announcements, product launches, and sales campaigns."

  Decision rule — ask exactly one question: **did the recipient already ask for, sign up for, or
  become part of the specific thing this message is about?**

  - If yes: this can be UTILITY. Strip anything persuasive and keep only the confirmation,
    update, reminder, or instruction relevant to what they already started.
  - If no — the message is inviting them into something they have not yet joined (a new
    programme, a new event, a new service, "come check this out") — it is fundamentally
    MARKETING, and no amount of rewording the tone changes that. Say so honestly in
    `suggested_category` rather than forcing a UTILITY label onto a message that will not
    survive Meta's review.

  Signals that push toward MARKETING even after a rewrite: calls to action to do something new
  ("apply now", "register today", "join us"), superlatives and urgency ("don't miss out",
  "limited time", "act now"), broad announcements not tied to one recipient's specific situation,
  and asking someone to opt back in after having gone silent.

  Signals that support UTILITY: a specific reference the recipient will recognise (a date, an
  appointment, an application status, an order or ticket number, a scheme they are enrolled in),
  language that informs or confirms rather than persuades, and no request to do something they
  have not already agreed to do.

  ## Hard constraints — do not violate these

  1. Preserve every `{{1}}`, `{{2}}`, … placeholder in the body exactly: same tokens, same
     count, same left-to-right order as the input body. Never add, remove, renumber, or reorder
     a placeholder, and never introduce a new one.
  2. Rewrite the BODY only. Never propose new button text or footer text — those are not part of
     your output and are not shown to you for editing.
  3. Keep the rewritten body concise. The body, buttons, and footer together are held to a combined
     1024-character budget by the messaging provider; a rewrite that is not at least as compact
     as the original risks going over it.
  4. `suggested_category` must be exactly `UTILITY` or exactly `MARKETING` — nothing else.

  ## Audience and tone

  The people sending this message are staff at small Indian non-profits. The people receiving it
  are the beneficiaries they serve — often people using a smartphone for messaging for the first
  time, sometimes with limited reading fluency. Write the way a helpful, unhurried government or
  NGO office notice would read: plain words, short sentences, respectful and calm. This is not an
  advertisement — do not add urgency, hype, or persuasive flourish. Match the original body's use
  or non-use of emoji; do not add emoji that were not already there, and do not remove ones that
  were.

  ## Input format

  The message you receive is a WhatsApp template draft encoded as plain text, in this layout:

      LABEL: <a short internal name for the template, or "(none)">

      BODY:
      <the current body text, possibly containing {{1}}, {{2}}, … placeholders>

      FOOTER: <the current footer text, or "(none)">

      BUTTONS:
      <one numbered line per button's visible text, or "(none)">

  If a `PREVIOUS ATTEMPT REJECTED` section follows, an earlier rewrite of this same draft failed
  an automated check for the stated reason. Treat that reason as authoritative: fix exactly that
  problem and change nothing else you would not otherwise have changed.

  ## Output format

  Return:

  - `body` — the rewritten body text. This is the only field that may change relative to the
    input; everything else in the draft (label, footer, buttons) stays as the sender already has
    it.
  - `suggested_category` — `UTILITY` if your rewrite qualifies per the rules above, or
    `MARKETING` if it honestly cannot (explain why in `changes`).
  - `changes` — one entry per meaningful change you made, each with:
      - `what_changed` — a short, concrete description of the edit (e.g. "Removed 'Don't miss
        this opportunity!' and the exclamation mark").
      - `why` — why that edit was necessary for UTILITY eligibility or for the audience/tone
        guidance above.
      - `best_practice` — the general rule this edit follows, phrased so it is useful the next
        time someone drafts a template (e.g. "Utility templates should state a fact about the
        recipient's own request, not invite them to something new.").
      - `best_practice_url` — an official WhatsApp Business Platform or Meta for Developers
        documentation URL, only if you are confident one exists and it directly supports this
        practice. Omit this field entirely rather than guess or invent a URL.

  If the body already fully qualifies as-is, return it unchanged with an empty `changes` list
  rather than making a cosmetic edit to have something to report.

  ## Example

  Input body: "Hey! 🎉 We've launched a brand-new nutrition workshop series — sign up today and
  don't miss out on the first session!"

  This invites the recipient into something new they have not joined, so it stays MARKETING —
  reword it for plain, calm tone, but do not claim UTILITY:

  - `suggested_category`: `MARKETING`
  - a `changes` entry noting the removal of "sign up today and don't miss out" and the
    exclamation marks, with `why` explaining it is still an invitation to something new so it
    cannot be UTILITY regardless of tone.

  Input body: "Hi {{1}}! Your appointment at the {{2}} clinic on {{3}} is confirmed. Reply STOP
  to cancel."

  This confirms something the recipient already booked, so it qualifies as UTILITY as written —
  return it unchanged with `changes: []`.
  """

  @doc "Returns \"template_utility_rewrite\"."
  @spec name() :: String.t()
  @impl true
  def name, do: "template_utility_rewrite"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description,
    do: "Rewrites a WhatsApp HSM draft's body for UTILITY-category eligibility and explains why."

  @doc false
  @spec model() :: String.t()
  @impl true
  def model, do: "anthropic:claude-sonnet-5"

  @doc false
  @spec system_prompt(map()) :: String.t()
  @impl true
  def system_prompt(_input), do: @meta_prompt

  @doc false
  @spec output_schema() :: keyword()
  @impl true
  def output_schema do
    [
      body: [type: :string, required: true, doc: "The rewritten template body."],
      suggested_category: [
        type: :string,
        required: true,
        doc: "Either \"UTILITY\" or \"MARKETING\"."
      ],
      changes: [
        type:
          {:list,
           {:map,
            [
              what_changed: [type: :string, required: true],
              why: [type: :string, required: true],
              best_practice: [type: :string, required: true],
              best_practice_url: [type: :string]
            ]}},
        required: true,
        doc: "One entry per meaningful edit made to the body."
      ]
    ]
  end

  @doc false
  @spec max_steps() :: pos_integer()
  @impl true
  def max_steps, do: 2

  @doc false
  @spec required_role() :: Skill.role()
  @impl true
  def required_role, do: :staff

  @doc false
  @spec feature_flag() :: atom()
  @impl true
  def feature_flag, do: :is_template_utility_rewrite_enabled

  @doc "Requires a non-empty encoded draft under the \"message\" key."
  @spec validate_input(map()) :: {:ok, map()} | {:error, String.t()}
  @impl true
  def validate_input(%{"message" => message} = input) when is_binary(message) and message != "",
    do: {:ok, input}

  def validate_input(_input), do: {:error, "message is required"}
end
