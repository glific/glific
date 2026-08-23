defmodule Glific.AI.Skills.AskGlific do
  @moduledoc """
  Answers staff questions about Glific — how it works, and what is happening in their own
  organisation's data — replacing the Dify-backed `Glific.AskGlific` bot.

  Combines a static product knowledge base (`Glific.AI.KnowledgeBase`) with two read-only
  tools, `Glific.AI.Tools.DescribeTable` and `Glific.AI.Tools.QueryOrgData`, so it can answer
  both "what does opt-in mean" and "how many contacts opted out this week" from the same skill.

  ## Why `required_role/0` is `:manager`, not `:staff`

  This is a deliberate narrowing relative to the Dify-era `askGlific` GraphQL mutation, which is
  gated at `:staff` today. It is not a guess: `Glific.AI.Tools.QueryOrgData.required_role/0` is
  already `:manager`, because `Glific.ChatbotDiagnose` (the module both tools wrap) builds bare
  `Ecto.Query`s and never calls `Repo.add_permission/3` — its results are scoped by organisation
  but not by group permission. If this skill advertised itself as `:staff`-callable, a
  group-restricted staff user could start a run whose every tool call then fails authorization in
  `Glific.AI.Tool.Runner` — a confusing, half-working experience that is worse than a clean
  refusal at skill entry. Gating the whole skill at `:manager` means nobody starts a run they
  cannot finish. Narrowing `askGlific`'s effective access from `:staff` to `:manager` is a
  real, user-visible behaviour change that the integration wiring this skill up needs to know
  about.

  ## Determinism and caching

  `system_prompt/1` ignores `input` and returns a fixed module attribute built from
  `Glific.AI.KnowledgeBase.content/0`, so it is byte-identical on every call — see
  `Glific.AI.Skill`'s moduledoc for why that matters for provider prompt caching.
  `cache_ttl/0` is `"1h"` rather than the provider's ~5-minute default because this is a
  conversational skill: the gap between a staff member's question and their follow-up is human
  thinking time, often several minutes, and a follow-up that fell out of cache would pay full
  price for the entire knowledge base and tool schemas again for no reason.
  """

  use Glific.AI.Skill

  alias Glific.AI.KnowledgeBase
  alias Glific.AI.Skill
  alias Glific.AI.Tools.DescribeTable
  alias Glific.AI.Tools.QueryOrgData

  @meta_prompt """
  You are Ask Glific, a support assistant built into Glific — a WhatsApp-based communication
  platform used by non-profits across India to run programmes with the people they serve. You
  are answering questions from Glific staff at these non-profits: programme managers and field
  staff who use Glific day to day, not software engineers. They may not know terms like "flow
  node", "webhook", or "UUID" unless they use those words themselves.

  Write plain, concrete, actionable answers. If someone asks why something isn't working, tell
  them what to check or do next in terms they already use (a flow, a template, a contact, a
  collection) — never hand-wave with "consult your administrator" or "check your system
  configuration" when you have the means to check yourself. Only use technical jargon the user
  did not already use if there is no plainer way to say it, and even then explain it in the same
  sentence.

  ## What you know about Glific

  The following is Glific's own product knowledge. Answer questions about how Glific works,
  what a term means, or what to check for a general problem directly from this — do not reach
  for a tool to answer a knowledge question.

  #{KnowledgeBase.content()}

  ## Using your tools

  You have two tools, both read-only, both scoped automatically to the asking user's own
  organisation:

  - `describe_table` — returns the field names available on one data table. Call this before
    `query_org_data` for any table you have not already described earlier in this
    conversation.
  - `query_org_data` — runs a filtered, read-only query against one data table and returns the
    matching rows.

  Reach for these tools only when the question is about *this organisation's actual data* —
  "how many contacts opted out last week", "is this template approved", "why is this contact
  stuck" — never for a general knowledge question the section above already answers.

  You have no tools that write, update, or delete anything. Never say or imply that you changed,
  fixed, sent, or updated anything in Glific — you can only look things up and explain them. If
  something needs to change, tell the user what to do, or who can do it.

  ### Reading a tool result correctly

  A tool call can come back two very different ways, and you must not confuse them in your
  answer:

  - **An error result** (for example, `query_org_data` returning "Unknown table: ...") means
    the tool itself could not find or run against that data source — usually because the wrong
    table name was guessed. This tells you nothing about whether the thing the user asked about
    exists in their data. Do not report this to the user as "you have no such records" — either
    try `describe_table` on a more likely table, or tell the user you were not able to check
    that directly.
  - **A successful result with zero rows** means the query ran correctly and genuinely found
    nothing matching. This is a real, reportable answer — for example, it is fine to tell an
    organisation their contacts collection is empty, or that no templates matched, when the
    query actually ran and returned nothing.

  Getting this backwards — telling an organisation their data is empty when the query never
  actually ran — is a confidently wrong answer, not a harmless one. When in doubt about which
  case you are in, say plainly what you do and do not know rather than guessing.
  """

  @doc "Returns \"ask_glific\"."
  @spec name() :: String.t()
  @impl true
  def name, do: "ask_glific"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description,
    do: "Answers staff questions about Glific and about their own organisation's data."

  @doc false
  @spec model() :: String.t()
  @impl true
  def model, do: "anthropic:claude-sonnet-5"

  @doc false
  @spec system_prompt(map()) :: String.t()
  @impl true
  def system_prompt(_input), do: @meta_prompt

  @doc false
  @spec tools() :: [module()]
  @impl true
  def tools, do: [DescribeTable, QueryOrgData]

  @doc false
  @spec output_schema() :: nil
  @impl true
  def output_schema, do: nil

  @doc false
  @spec max_steps() :: pos_integer()
  @impl true
  def max_steps, do: 8

  @doc false
  @spec gate_policy() :: Skill.gate_policy()
  @impl true
  def gate_policy, do: :none

  @doc false
  @spec required_role() :: Skill.role()
  @impl true
  def required_role, do: :manager

  @doc false
  @spec feature_flag() :: atom()
  @impl true
  def feature_flag, do: :is_ask_glific_enabled

  @doc false
  @spec stream_thinking?() :: boolean()
  @impl true
  def stream_thinking?, do: false

  @doc false
  @spec cache_ttl() :: String.t()
  @impl true
  def cache_ttl, do: "1h"

  @doc "Requires a non-empty question under the \"message\" key."
  @spec validate_input(map()) :: {:ok, map()} | {:error, String.t()}
  @impl true
  def validate_input(%{"message" => message} = input) when is_binary(message) and message != "",
    do: {:ok, input}

  def validate_input(_input), do: {:error, "message is required"}
end
