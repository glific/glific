defmodule Glific.PromptGenerator do
  @moduledoc """
  Context for on-demand WhatsApp chatbot system-prompt generation.

  An NGO supplies answers to 9 questions; this context drives `Glific.AI.Skills.PromptGenerator`
  on the in-Glific AI agent runtime, synchronously, through `Glific.AI.Run.sync/3`, and persists
  the result. `generate_prompt/3` keeps its original signature and its
  `PromptGenerationRequest` row lifecycle (`:in_progress` -> `:ready`/`:failed`) unchanged, so the
  pollable `prompt_generation(id)` query and the existing `PromptGeneratorModal` frontend keep
  working exactly as before — only the engine underneath changed, from an async Kaapi round trip
  to a synchronous in-process model call.

  ## Why the row still passes through `:in_progress`

  The row briefly exists in `:in_progress` even though generation now completes before
  `generate_prompt/3` returns, because `apply_callback/2` — the function that resolves a row to
  `:ready`/`:failed` — is shared with `handle_callback/1` below and is not worth forking into two
  copies for a state transition that is otherwise identical. `create_prompt_request/1` inserts
  the row, then the very same call transitions it via `apply_callback/2` before returning.

  ## `handle_callback/1` is now legacy

  `handle_callback/1`, `apply_callback/2`'s Kaapi-callback-shaped `params`, and the
  `POST /kaapi/prompt_generation` route (`GlificWeb.KaapiController.prompt_generation_callback/2`)
  are kept, unchanged, purely because the router and controller still reference
  `handle_callback/1` and are outside this module's remit to edit. Nothing in this codebase will
  ever POST to that route again: `generate_prompt/3` no longer sends a `request_id`/callback URL
  to Kaapi, so no external caller can supply a `metadata.request_id` that correlates to a real
  row. This code path is orphaned, not deleted — see the PR/commit notes for the follow-up to
  remove the route, the controller action, and this function together.

  ## A deliberate behavior change: `user_id` is no longer optional in practice

  Every real caller (`GlificWeb.Resolvers.PromptGenerator.generate/3`) already supplies
  `user.id`. `user_id` now names the identity the AI runtime runs the skill as — for
  authorization (`required_role/0`) and for the acting-user audit trail `Glific.AI.Actor`
  establishes — so a `nil` `user_id` is no longer a request the Kaapi-less engine can serve; the
  old Kaapi engine only needed an organization id. Passing `nil` now returns `{:error, reason}`
  without inserting a row, the same as any other precondition failure below.
  """

  import Glific.SafeLog

  alias Glific.{
    AI.Run,
    PromptGenerator.PromptGenerationRequest,
    Repo,
    Users.User
  }

  defmodule Error do
    @moduledoc """
    Custom error for prompt-generation failures.

    Failures here are reported to AppSignal under the `"prompt_generator"` namespace rather
    than surfaced to a user (the resolver shapes what the caller sees), so we can build a
    dedicated error-rate trigger on the namespace.
    """
    defexception [:message, :reason, :organization_id]

    @spec message(%__MODULE__{}) :: String.t()
    def message(%Error{} = error) do
      "#{error.message} reason: #{error.reason} organization_id: #{error.organization_id}"
    end
  end

  # AppSignal namespace for prompt-generation errors (enables a dedicated error-rate trigger).
  @appsignal_namespace "prompt_generator"

  # Registry name of Glific.AI.Skills.PromptGenerator — Run.sync/3 takes the name, not the
  # module, so no compile-time alias to the skill module is needed here.
  @skill_name "prompt_generator"

  # Ordered list of {field_atom, label} for the 9 NGO questions. Labels match the few-shot
  # input keys in Glific.AI.Skills.PromptGenerator's system prompt so the model maps input to
  # output consistently.
  @answer_fields [
    {:name, "persona"},
    {:purpose, "objective"},
    {:audience, "audience"},
    {:language, "language"},
    {:tone, "tone"},
    {:format, "length"},
    {:off_limits, "skip_answer_topics"},
    {:fallback, "fallback_answer"},
    {:escalation, "escalation_details"}
  ]

  @doc """
  Generates a WhatsApp chatbot system prompt for the given NGO answers, as `user_id`.

  Drives `Glific.AI.Skills.PromptGenerator` synchronously through `Glific.AI.Run.sync/3`:
  `answers` is serialised by `format_answers/1` into the skill's single-string input, the model
  runs to completion inside this call, and the result is persisted through the same
  `apply_callback/2` transition `handle_callback/1` uses. Returns `{:ok, request}` with the row
  already resolved to `:ready` or `:failed` — the caller does not need to poll to see the
  outcome, though the `prompt_generation(id)` query still works for that if it wants to.

  Returns `{:error, reason}` — without inserting a row — when `user_id` cannot be resolved to a
  real user of `org_id` (see the moduledoc: a real acting user is required now that generation
  runs on the agent runtime, not merely an active Kaapi credential for the organization).

  The `:is_prompt_generator_enabled` feature flag gates access to this function at the GraphQL
  mutation layer, and is also enforced again inside `Glific.AI.Run.sync/3` via the skill's own
  `feature_flag/0` (see `Glific.AI.Skill.enabled?/2`).

  ## Parameters

    - `answers` — map with keys `:name`, `:purpose`, `:audience`, `:language`, `:tone`,
      `:format`, `:off_limits`, `:fallback`, `:escalation` (string values; blank entries
      are omitted from the model input).
    - `org_id` — organization ID (scopes the row and the user lookup).
    - `user_id` — the user to run the skill as; required (see the moduledoc).
  """
  @spec generate_prompt(map(), non_neg_integer(), non_neg_integer() | nil) ::
          {:ok, PromptGenerationRequest.t()} | {:error, any()}
  def generate_prompt(answers, org_id, user_id \\ nil) do
    with {:ok, user} <- fetch_user(user_id, org_id),
         {:ok, request} <-
           create_prompt_request(%{
             inputs: answers,
             status: :in_progress,
             request_id: Ecto.UUID.generate(),
             organization_id: org_id,
             user_id: user_id
           }) do
      apply_callback(request, run_params(answers, user))
    end
  end

  @doc """
  Handles the async callback POSTed by Kaapi after LLM completion.

  Legacy path, kept only because `GlificWeb.KaapiController.prompt_generation_callback/2` still
  calls it — see the moduledoc. Nothing calls into this from `generate_prompt/3` anymore.

  Looks up the `PromptGenerationRequest` by `metadata.request_id` (the UUID we generated and
  sent to Kaapi in `request_metadata.request_id`; Kaapi echoes it back). On `success: true`,
  sets `status: :ready` and `generated_prompt`. On failure (`success: false` or error present),
  sets `status: :failed` and `error_message`. Unknown `request_id` logs and returns an error.

  This function is idempotent: calling it twice on the same row is safe — the terminal-state
  guard returns `{:ok, request}` unchanged for rows already in `:ready` or `:failed`.

  The real callback shape (string-keyed after Plug JSON parsing):

  ```json
  {
    "success": true,
    "data": {
      "response": {
        "output": { "content": { "value": "<generated prompt text>" } }
      }
    },
    "metadata": { "request_id": "<uuid we sent>" }
  }
  ```

  ## Parameters

    - `params` — the parsed JSON body from Kaapi (string-keyed).
  """
  @spec handle_callback(map()) ::
          {:ok, PromptGenerationRequest.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def handle_callback(%{"metadata" => %{"request_id" => request_id}} = params) do
    # Org context is set from the callback subdomain (same as the knowledge-base
    # callback), so the lookup is scoped to the organization that owns the request.
    with {:ok, request} <- Repo.fetch_by(PromptGenerationRequest, %{request_id: request_id}),
         {:ok, updated} <- apply_callback(request, params) do
      {:ok, updated}
    else
      {:error, [_, "Resource not found"]} ->
        log_callback_error("No prompt generation request found for the callback",
          reason: "request_id=#{request_id}"
        )

        {:error, "Prompt generation request not found for request_id=#{request_id}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Defensive catch-all: the callback endpoint is public, so a malformed body must
  # not raise (the controller must still return 200). Kaapi sends a well-formed payload
  # with metadata.request_id; anything else is reported and ignored.
  def handle_callback(params) do
    log_callback_error("Unexpected prompt generation callback payload",
      reason: safe_inspect(params)
    )

    {:error, "Unexpected prompt generation callback payload"}
  end

  @doc """
  Formats the NGO answer map into a labelled Q→A string for the model.

  Blank, nil, or empty answers are omitted. Per-field length is validated and
  rejected at the resolver boundary (see `GlificWeb.Resolvers.PromptGenerator`), so
  this function does not clamp — it formats the answers as given.

  This is also the encoding `generate_prompt/3` sends as
  `Glific.AI.Skills.PromptGenerator`'s single string `"message"` input — see that skill's
  moduledoc for the seam this crosses.

  ## Examples

      iex> Glific.PromptGenerator.format_answers(%{name: "Pratham", purpose: ""})
      "- persona: Pratham\n"
  """
  @spec format_answers(map()) :: String.t()
  def format_answers(answers) do
    @answer_fields
    |> Enum.reduce("", fn {field, label}, acc ->
      value =
        answers[field] || answers[Atom.to_string(field)]

      if blank?(value) do
        acc
      else
        acc <> "- #{label}: #{value}\n"
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec fetch_user(non_neg_integer() | nil, non_neg_integer()) ::
          {:ok, User.t()} | {:error, String.t()}
  defp fetch_user(nil, _org_id), do: {:error, "A user is required to generate a prompt."}

  defp fetch_user(user_id, org_id) do
    case Repo.fetch_by(User, %{id: user_id, organization_id: org_id}) do
      {:ok, user} -> {:ok, user}
      {:error, _reason} -> {:error, "A user is required to generate a prompt."}
    end
  end

  # Runs the skill to completion and shapes the result into the same string-keyed envelope
  # apply_callback/2 already knows how to read (see its moduledoc's callback-shape example) —
  # this is what "apply_callback/2 is called directly instead of via HTTP" means in practice.
  @spec run_params(map(), User.t()) :: map()
  defp run_params(answers, user) do
    input = %{"message" => format_answers(answers)}

    case Run.sync(@skill_name, input, user) do
      {:ok, %{result: %{"generated_prompt" => text}}} when is_binary(text) ->
        success_params(text)

      {:ok, %{result: unexpected}} ->
        log_callback_error("Prompt generator skill returned an unexpected result shape",
          reason: safe_inspect(unexpected)
        )

        failure_params(:unexpected_result)

      {:error, reason} ->
        failure_params(reason)
    end
  end

  @spec success_params(String.t()) :: map()
  defp success_params(text) do
    %{
      "success" => true,
      "data" => %{"response" => %{"output" => %{"content" => %{"value" => text}}}}
    }
  end

  @spec failure_params(term()) :: map()
  defp failure_params(reason), do: %{"success" => false, "error" => run_error_message(reason)}

  @spec run_error_message(term()) :: String.t()
  defp run_error_message(reason)
       when reason in [:forbidden, :unknown_skill, :gated_skill, :feature_disabled],
       do: "Prompt generation is not available for this organization."

  defp run_error_message(reason) do
    log_callback_error("Prompt generator run failed", reason: safe_inspect(reason))
    "The prompt could not be generated right now. Please try again."
  end

  @spec create_prompt_request(map()) ::
          {:ok, PromptGenerationRequest.t()} | {:error, Ecto.Changeset.t()}
  defp create_prompt_request(attrs) do
    %PromptGenerationRequest{}
    |> PromptGenerationRequest.changeset(attrs)
    |> Repo.insert()
  end

  @spec apply_callback(PromptGenerationRequest.t(), map()) ::
          {:ok, PromptGenerationRequest.t()} | {:error, Ecto.Changeset.t()}
  # Terminal states are immutable: a late callback must not clobber a row that
  # already reached :ready (losing the generated prompt) or :failed.
  defp apply_callback(%PromptGenerationRequest{status: status} = request, _params)
       when status in [:ready, :failed],
       do: {:ok, request}

  defp apply_callback(request, %{"success" => true} = params) do
    generated_prompt = get_in(params, ["data", "response", "output", "content", "value"])

    request
    |> PromptGenerationRequest.changeset(%{
      status: :ready,
      generated_prompt: generated_prompt
    })
    |> Repo.update()
    |> record_outcome("success")
  end

  defp apply_callback(request, params) do
    error_message =
      case params["error"] do
        nil -> safe_inspect(params["errors"])
        msg -> msg
      end

    request
    |> PromptGenerationRequest.changeset(%{
      status: :failed,
      error_message: error_message
    })
    |> Repo.update()
    |> record_outcome("failure")
  end

  # Track generation latency (dispatch -> resolution) and the success/failure count in
  # AppSignal, mirroring the flow-webhook telemetry (track_webhook_count/latency). Only
  # fires on a real transition — the terminal-state guard short-circuits duplicate callbacks.
  @spec record_outcome(
          {:ok, PromptGenerationRequest.t()} | {:error, Ecto.Changeset.t()},
          String.t()
        ) :: {:ok, PromptGenerationRequest.t()} | {:error, Ecto.Changeset.t()}
  defp record_outcome({:ok, request} = result, status) do
    duration_ms = DateTime.diff(DateTime.utc_now(), request.inserted_at, :millisecond)
    Appsignal.increment_counter("prompt_generator_count", 1, %{status: status})
    Appsignal.add_distribution_value("prompt_generator_latency", duration_ms, %{status: status})
    result
  end

  defp record_outcome({:error, changeset} = result, status) do
    log_callback_error("Failed to persist prompt generation as :#{status}",
      reason: safe_inspect(changeset)
    )

    result
  end

  defp record_outcome(result, _status), do: result

  @spec log_callback_error(String.t(), keyword()) :: :ok
  defp log_callback_error(message, opts) do
    Glific.log_exception(
      %Error{message: message, reason: Keyword.get(opts, :reason)},
      namespace: @appsignal_namespace
    )
  end

  @spec blank?(any()) :: boolean()
  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
