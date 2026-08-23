defmodule Glific.Templates.UtilityRewriter do
  @moduledoc """
  Drives `Glific.AI.Skills.TemplateUtilityRewrite` to rewrite a draft HSM template's body for
  WhatsApp UTILITY-category eligibility, and enforces the hard constraints the rewrite must
  satisfy before it is handed back to the caller.

  This is create/draft-flow tooling only — an approved HSM is locally immutable
  (`Glific.Templates.SessionTemplate`, see `lib/glific/templates/session_templates.ex:159-176`),
  so nothing here writes to a `SessionTemplate`; `rewrite/2` only returns text for the caller to
  put back into its own draft form.

  ## Why validation lives here, not in the skill

  The skill (`Glific.AI.Skills.TemplateUtilityRewrite`) only describes the model call — the
  prompt, the schema, gating. The three checks below are things a bad rewrite fails *late*, as a
  Gupshup 400 at submit time (`lib/glific/providers/gupshup/template.ex:75-78`), so they are
  enforced here, in code, before a rewrite is ever shown to a user:

    1. The rewritten body's `{{n}}` placeholders are exactly the input body's, same count and
       order — otherwise the draft's existing `example`/`variables` go stale.
    2. Body + buttons + footer stays within the BSP's combined 1024-character budget.
    3. `suggested_category` is one of `Glific.Templates.list_whatsapp_hsm_categories/0` — the
       create path has no server-side category validation, so this is the only gate on it.

  A fourth constraint — buttons are never rewritten — is enforced by construction: the model is
  never shown button text as something to edit (see the skill's system prompt), and this module
  only ever returns `body`/`suggested_category`/`changes`, never buttons.

  A violation triggers exactly one retry, with the violation fed back to the model as plain text
  (see `encode_draft/2`); a second violation is returned as a field-level error rather than
  retried again, so a stuck rewrite fails fast instead of quietly consuming further model calls.
  """

  alias Glific.AI.Run
  alias Glific.Templates
  alias Glific.Users.User

  @typedoc "A draft session template being considered for a UTILITY-category rewrite."
  @type draft :: %{
          label: String.t() | nil,
          body: String.t(),
          footer: String.t() | nil,
          buttons: [String.t()]
        }

  @typedoc "One explained edit to the body."
  @type change :: %{
          what_changed: String.t(),
          why: String.t(),
          best_practice: String.t(),
          best_practice_url: String.t() | nil
        }

  @typedoc "A successful rewrite."
  @type rewrite :: %{body: String.t(), suggested_category: String.t(), changes: [change()]}

  @typedoc "A field-level error, shaped like `GlificWeb.Resolvers.AI.error_ack/2`'s entries."
  @type field_error :: %{key: String.t(), message: String.t()}

  @skill_name "template_utility_rewrite"
  @max_attempts 2
  @character_budget 1024
  @button_text_limit 20
  # Mirrors Glific.Templates' private button-character-class checks (contains_variable?/1,
  # contains_newline?/1, contains_formatting?/1, contains_emoji?/1) — duplicated rather than
  # called into, since those are `defp` and this module is scoped to add only a thin delegation
  # to Glific.Templates, not to widen its public API.
  @emoji_regex ~r/[\x{1F600}-\x{1F64F}|\x{1F300}-\x{1F5FF}|\x{1F680}-\x{1F6FF}|\x{1F700}-\x{1F77F}|\x{1F780}-\x{1F7FF}|\x{1F800}-\x{1F8FF}|\x{1F900}-\x{1F9FF}|\x{1FA00}-\x{1FA6F}|\x{1FA70}-\x{1FAFF}|\x{2600}-\x{26FF}|\x{2700}-\x{27BF}|\x{1F1E6}-\x{1F1FF}]/u
  @variable_regex ~r/\{\{\d+\}\}/

  @doc """
  Rewrites `params`' body for WhatsApp UTILITY-category eligibility, as `user`.

  `params` takes `:body` (required), and optional `:footer`, `:buttons` (a list of button
  texts), and `:label`. Retries once, feeding the violation back to the model, when the model's
  rewrite fails one of the module's hard checks; a second failure is a field-level error.
  """
  @spec rewrite(map(), User.t()) :: {:ok, rewrite()} | {:error, [field_error()]}
  def rewrite(params, %User{} = user) do
    with {:ok, draft} <- normalize(params),
         :ok <- validate_buttons(draft.buttons) do
      attempt(draft, user, 1, nil)
    end
  end

  @spec normalize(map()) :: {:ok, draft()} | {:error, [field_error()]}
  defp normalize(params) do
    case Map.get(params, :body) do
      body when is_binary(body) ->
        case String.trim(body) do
          "" -> {:error, [error("body", "Body is required.")]}
          trimmed -> {:ok, do_normalize(trimmed, params)}
        end

      _missing ->
        {:error, [error("body", "Body is required.")]}
    end
  end

  @spec do_normalize(String.t(), map()) :: draft()
  defp do_normalize(body, params) do
    %{
      label: Map.get(params, :label),
      body: body,
      footer: Map.get(params, :footer),
      buttons: Map.get(params, :buttons) || []
    }
  end

  @spec validate_buttons([String.t()]) :: :ok | {:error, [field_error()]}
  defp validate_buttons(buttons) do
    if Enum.any?(buttons, &invalid_button_text?/1) do
      {:error,
       [
         error(
           "buttons",
           "Button text must be #{@button_text_limit} characters or fewer, and free of " <>
             "variables, newlines, emoji, and *_~ formatting."
         )
       ]}
    else
      :ok
    end
  end

  @spec invalid_button_text?(String.t()) :: boolean()
  defp invalid_button_text?(text) do
    String.length(text) > @button_text_limit or
      String.contains?(text, "\n") or
      Regex.match?(@variable_regex, text) or
      Regex.match?(~r/[*_~]/, text) or
      Regex.match?(@emoji_regex, text)
  end

  @spec attempt(draft(), User.t(), pos_integer(), String.t() | nil) ::
          {:ok, rewrite()} | {:error, [field_error()]}
  defp attempt(draft, user, attempt_number, violation) do
    input = %{"message" => encode_draft(draft, violation)}

    case Run.sync(@skill_name, input, user) do
      {:ok, %{result: object}} -> handle_result(object, draft, user, attempt_number)
      {:error, reason} -> {:error, [run_error(reason)]}
    end
  end

  @spec handle_result(map(), draft(), User.t(), pos_integer()) ::
          {:ok, rewrite()} | {:error, [field_error()]}
  defp handle_result(object, draft, user, attempt_number) do
    case check(object, draft) do
      :ok ->
        {:ok, shape(object)}

      {:error, violation} when attempt_number < @max_attempts ->
        attempt(draft, user, attempt_number + 1, violation)

      {:error, violation} ->
        {:error, [error("body", violation)]}
    end
  end

  @spec check(map(), draft()) :: :ok | {:error, String.t()}
  defp check(%{"body" => new_body, "suggested_category" => category}, draft)
       when is_binary(new_body) and is_binary(category) do
    with :ok <- check_variables(draft.body, new_body),
         :ok <- check_length(new_body, draft) do
      check_category(category)
    end
  end

  defp check(_object, _draft), do: {:error, "The model did not return a body and category."}

  @spec check_variables(String.t(), String.t()) :: :ok | {:error, String.t()}
  defp check_variables(original_body, new_body) do
    if variables(original_body) == variables(new_body) do
      :ok
    else
      {:error,
       "The rewritten body must keep exactly the same {{n}} placeholders, in the same count " <>
         "and order, as the original body."}
    end
  end

  @spec variables(String.t()) :: [String.t()]
  defp variables(text), do: Regex.scan(@variable_regex, text) |> Enum.map(&hd/1)

  @spec check_length(String.t(), draft()) :: :ok | {:error, String.t()}
  defp check_length(new_body, %{footer: footer, buttons: buttons}) do
    total =
      String.length(new_body) + String.length(footer || "") + buttons_length(buttons)

    if total <= @character_budget do
      :ok
    else
      {:error,
       "The rewritten body, combined with the footer and button text, must total " <>
         "#{@character_budget} characters or fewer (currently #{total}). Make the body shorter."}
    end
  end

  @spec buttons_length([String.t()]) :: non_neg_integer()
  defp buttons_length(buttons), do: Enum.reduce(buttons, 0, &(String.length(&1) + &2))

  @spec check_category(String.t()) :: :ok | {:error, String.t()}
  defp check_category(category) do
    valid_categories = Templates.list_whatsapp_hsm_categories()

    if category in valid_categories do
      :ok
    else
      {:error, "suggested_category must be one of: #{Enum.join(valid_categories, ", ")}."}
    end
  end

  @spec shape(map()) :: rewrite()
  defp shape(%{"body" => body, "suggested_category" => category} = object) do
    %{
      body: body,
      suggested_category: category,
      changes: object |> Map.get("changes", []) |> Enum.map(&shape_change/1)
    }
  end

  @spec shape_change(map()) :: change()
  defp shape_change(change) do
    %{
      what_changed: Map.get(change, "what_changed"),
      why: Map.get(change, "why"),
      best_practice: Map.get(change, "best_practice"),
      best_practice_url: Map.get(change, "best_practice_url")
    }
  end

  @spec run_error(term()) :: field_error()
  defp run_error(reason) when reason in [:forbidden, :unknown_skill, :gated_skill],
    do: error("skill", "This feature is not available.")

  defp run_error(reason) do
    Glific.log_error(
      "Glific.Templates.UtilityRewriter rewrite failed: #{Glific.SafeLog.safe_inspect(reason)}"
    )

    error("body", "The rewrite could not be completed right now. Please try again.")
  end

  @spec error(String.t(), String.t()) :: field_error()
  defp error(key, message), do: %{key: key, message: message}

  # The `message` seam Glific.AI.Runtime derives input from accepts only a single string (see
  # Glific.AI.Skills.TemplateUtilityRewrite's moduledoc), so the draft is serialised into one
  # deterministic, unambiguous layout the skill's system prompt documents how to parse.
  @spec encode_draft(draft(), String.t() | nil) :: String.t()
  defp encode_draft(draft, violation) do
    [
      "LABEL: #{presence(draft.label)}",
      "",
      "BODY:",
      draft.body,
      "",
      "FOOTER: #{presence(draft.footer)}",
      "",
      "BUTTONS:",
      encode_buttons(draft.buttons)
    ]
    |> Enum.join("\n")
    |> append_violation(violation)
  end

  @spec presence(String.t() | nil) :: String.t()
  defp presence(nil), do: "(none)"
  defp presence(""), do: "(none)"
  defp presence(text), do: text

  @spec encode_buttons([String.t()]) :: String.t()
  defp encode_buttons([]), do: "(none)"

  defp encode_buttons(buttons),
    do: buttons |> Enum.with_index(1) |> Enum.map_join("\n", fn {text, i} -> "#{i}. #{text}" end)

  @spec append_violation(String.t(), String.t() | nil) :: String.t()
  defp append_violation(encoded, nil), do: encoded

  defp append_violation(encoded, violation) do
    encoded <>
      "\n\nPREVIOUS ATTEMPT REJECTED\nReason: #{violation}\n" <>
      "Regenerate the BODY only, fixing exactly that problem. Keep everything else about " <>
      "your rewrite as close to your best judgement as possible."
  end
end
