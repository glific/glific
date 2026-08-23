defmodule Glific.AI.Graders do
  @moduledoc """
  Deterministic graders for AI skill evals (`test/glific/ai/evals/`).

  Every function here except `judge/3` is a pure function that makes no model call and no I/O
  beyond what its arguments already carry — given the same arguments, a grader always returns
  the same verdict, which is what makes it safe to run in CI on every PR
  (`mix test --only eval`). Each returns `:ok | {:error, reason}` rather than a bare boolean, so
  a failing eval assertion tells you *what* was wrong instead of just that something was.

  `judge/3` is the one exception: it calls a real model and is only meaningful in the
  `:eval_live` tier — see its own doc.
  """

  alias Glific.AI
  alias Glific.AI.Conversation
  alias Glific.AI.Message
  alias Glific.AI.Model.ReqLLM, as: LiveModel
  alias Glific.AI.Model.Result
  alias Glific.AI.Run
  alias Glific.AI.Skill

  @judge_model "anthropic:claude-sonnet-5"
  @judge_prompt_path "test/support/fixtures/ai/evals/judge/v1.txt"

  @doc """
  Extracts the plain text a skill's raw output carries, for the text-based graders below.

  Handles a `ReqLLM.Message`-shaped output (the `Glific.AI.Skill` result for a skill with no
  `output_schema/0`, e.g. `Glific.AI.Skills.Echo`) and a plain string. Anything else is not a
  text output and has no text to extract.
  """
  @spec output_text(term()) :: String.t()
  def output_text(text) when is_binary(text), do: text

  def output_text(%{content: parts}) when is_list(parts) do
    parts
    |> Enum.filter(&(Map.get(&1, :type) == :text))
    |> Enum.map_join("", &Map.get(&1, :text, ""))
  end

  @doc "Asserts `text` contains `substring`."
  @spec contains(String.t(), String.t()) :: :ok | {:error, String.t()}
  def contains(text, substring) when is_binary(text) and is_binary(substring) do
    if String.contains?(text, substring),
      do: :ok,
      else: {:error, "expected #{inspect(text)} to contain #{inspect(substring)}"}
  end

  @doc "Asserts `text` matches `pattern` (a `Regex` or a string compiled with `Regex.compile!/1`)."
  @spec matches(String.t(), Regex.t() | String.t()) :: :ok | {:error, String.t()}
  def matches(text, %Regex{} = pattern) when is_binary(text) do
    if Regex.match?(pattern, text),
      do: :ok,
      else: {:error, "expected #{inspect(text)} to match #{inspect(pattern)}"}
  end

  def matches(text, pattern) when is_binary(text) and is_binary(pattern),
    do: matches(text, Regex.compile!(pattern))

  @doc "Asserts a run's `steps` did not exceed `max`."
  @spec max_steps(Run.outcome(), pos_integer()) :: :ok | {:error, String.t()}
  def max_steps(%{steps: steps}, max) when is_integer(max) do
    if steps <= max,
      do: :ok,
      else: {:error, "expected steps (#{steps}) to be within the budget (#{max})"}
  end

  @doc """
  Asserts no tool call in `conversation`'s stored transcript falls outside `skill`'s
  `tools/0` allowlist.

  Reads `ai_messages` back through `Glific.AI.list_messages/2` and `Glific.AI.Codec.decode/1` —
  the same source of truth the runtime itself replays from — rather than a mock, so this catches
  a skill that calls a tool it never declared just as reliably as it would in production.
  """
  @spec tools_within_allowlist(Conversation.t(), module()) :: :ok | {:error, String.t()}
  def tools_within_allowlist(%Conversation{id: conversation_id}, skill) do
    allowed = skill.tools() |> Enum.map(& &1.name()) |> MapSet.new()

    called =
      conversation_id
      |> AI.list_messages()
      |> Enum.flat_map(&decoded_tool_call_names/1)
      |> MapSet.new()

    disallowed = called |> MapSet.difference(allowed) |> MapSet.to_list()

    if disallowed == [],
      do: :ok,
      else: {:error, "called tool(s) outside the allowlist: #{inspect(disallowed)}"}
  end

  @doc """
  Asserts `output` satisfies `schema`, a skill's `output_schema/0`.

  `nil` (free-text output, no structured schema declared) trivially passes — there is nothing to
  validate against. A non-nil schema is converted to JSON Schema the same way
  `Glific.AI.Model.ReqLLM` prepares it for a provider (`ReqLLM.Schema.to_json/1`), then checked
  with the same validator (`JSV`) `req_llm` itself uses to coerce/validate structured output.
  """
  @spec validates_against_schema(term(), Skill.output_schema()) :: :ok | {:error, String.t()}
  def validates_against_schema(_output, nil), do: :ok

  def validates_against_schema(output, schema) do
    built = schema |> ReqLLM.Schema.to_json() |> JSV.build!()

    case JSV.validate(output, built) do
      {:ok, _validated} -> :ok
      {:error, error} -> {:error, "output does not satisfy schema: #{inspect(error)}"}
    end
  end

  @doc """
  Asserts the `{{n}}` template-variable token set — same tokens, same count, same order — is
  identical between `before_text` and `after_text`.

  Generic over two plain strings so it is reusable outside the echo skill this file otherwise
  tests — written for `Glific.AI.Skills.TemplateUtilityRewrite` (Phase 2), which rewrites an HSM
  body and must not drop, add, reorder, or duplicate a `{{n}}` placeholder.
  """
  @spec template_variables_preserved(String.t(), String.t()) :: :ok | {:error, String.t()}
  def template_variables_preserved(before_text, after_text)
      when is_binary(before_text) and is_binary(after_text) do
    before_tokens = template_tokens(before_text)
    after_tokens = template_tokens(after_text)

    if before_tokens == after_tokens do
      :ok
    else
      {:error,
       "template variables changed: #{inspect(before_tokens)} -> #{inspect(after_tokens)}"}
    end
  end

  @doc """
  Asserts a template's body, plus the summed length of every button's text, plus its footer,
  stays within WhatsApp's 1024-character HSM limit.

  Accepts a map with `:body` (required), `:buttons` (a list of button-text strings, default
  `[]`) and `:footer` (default `nil`) — atom-keyed so a skill's already-validated output can be
  passed straight through without a translation step.
  """
  @spec template_length_within_limit(%{
          optional(:buttons) => [String.t()],
          optional(:footer) => String.t() | nil,
          :body => String.t()
        }) :: :ok | {:error, String.t()}
  def template_length_within_limit(%{body: body} = template) when is_binary(body) do
    buttons = Map.get(template, :buttons, [])
    footer = Map.get(template, :footer)

    total =
      String.length(body) +
        Enum.reduce(buttons, 0, fn text, acc -> acc + String.length(text) end) +
        String.length(footer || "")

    if total <= 1024,
      do: :ok,
      else: {:error, "template length #{total} exceeds the 1024-character limit"}
  end

  @doc """
  LLM-as-judge: scores `output` against a natural-language `rubric` on a 0.0-1.0 scale and
  passes if the score is at least `threshold`.

  **Live-tier only.** This makes a real, billable provider call — it is meaningless in the
  stubbed tier (grading a canned response tells you nothing) and must never run in CI. It is
  not gated by an internal `:eval_live` tag check (a plain function cannot see which ExUnit tag
  the calling test is running under); the gate is that it requires a real provider credential
  (`ANTHROPIC_API_KEY` in the environment, the same variable `codec_live_test.exs` checks for)
  and calls `Glific.AI.Model.ReqLLM` directly — bypassing `Glific.AI.Model`'s configured adapter,
  which `config/test.exs` forces to `Glific.AI.Model.Stub` — so it is unusable anywhere the
  default test config and CI's environment apply. Call it only from an `:eval_live`-tagged test.

  The judge prompt is a versioned fixture (`#{@judge_prompt_path}`), not an inline string here,
  because a judge whose prompt drifts silently invalidates every prior score — a change to the
  prompt should be a reviewable diff to that file, not a hidden edit to this function.
  """
  @spec judge(String.t(), String.t(), number()) ::
          {:ok, %{score: float(), passed: boolean(), rationale: String.t()}} | {:error, term()}
  def judge(output, rubric, threshold)
      when is_binary(output) and is_binary(rubric) and is_number(threshold) do
    with {:ok, api_key} <- judge_api_key(),
         prompt = render_judge_prompt(output, rubric),
         context = ReqLLM.Context.new([ReqLLM.Context.user(prompt)]),
         {:ok, result} <- LiveModel.chat(context, model: @judge_model, api_key: api_key),
         {:ok, score, rationale} <- parse_judge_response(result) do
      {:ok, %{score: score, rationale: rationale, passed: score >= threshold}}
    end
  end

  @spec judge_api_key() :: {:ok, String.t()} | {:error, :missing_live_credentials}
  defp judge_api_key do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, :missing_live_credentials}
    end
  end

  @spec render_judge_prompt(String.t(), String.t()) :: String.t()
  defp render_judge_prompt(output, rubric) do
    @judge_prompt_path
    |> File.read!()
    |> String.replace("{{output}}", output)
    |> String.replace("{{rubric}}", rubric)
  end

  @spec parse_judge_response(Result.t()) :: {:ok, float(), String.t()} | {:error, term()}
  defp parse_judge_response(%{message: message}) do
    text = output_text(message)

    case Jason.decode(text) do
      {:ok, %{"score" => score} = decoded} ->
        {:ok, score * 1.0, Map.get(decoded, "rationale", "")}

      _unparseable ->
        {:error, {:unparseable_judge_response, text}}
    end
  end

  @spec decoded_tool_call_names(Message.t()) :: [String.t()]
  defp decoded_tool_call_names(%{parts: parts}) do
    case AI.Codec.decode(parts) do
      {:ok, %{tool_calls: tool_calls}} when is_list(tool_calls) ->
        Enum.map(tool_calls, & &1.function.name)

      _no_tool_calls ->
        []
    end
  end

  @spec template_tokens(String.t()) :: [String.t()]
  defp template_tokens(text) do
    ~r/\{\{\s*[^{}]+?\s*\}\}/ |> Regex.scan(text) |> List.flatten()
  end
end
