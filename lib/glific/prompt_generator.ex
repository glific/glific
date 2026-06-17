defmodule Glific.PromptGenerator do
  @moduledoc """
  Context for on-demand WhatsApp chatbot system-prompt generation.

  An NGO supplies answers to 9 questions; this context calls Kaapi's async LLM
  service and persists the request. When Kaapi completes, it POSTs back to
  `/kaapi/prompt_generation` (wired in M2) and `handle_callback/1` updates the row.

  ## Flow

      1. `generate_prompt/3` — build payload, call Kaapi, persist `:in_progress` row.
      2. Kaapi processes asynchronously and POSTs to the callback URL.
      3. `handle_callback/1` — look up by `kaapi_job_id`, update status + text/error.
  """

  alias Glific.{
    Partners,
    Repo
  }

  alias Glific.PromptGenerator.PromptGenerationRequest
  alias Glific.ThirdParty.Kaapi

  defmodule Error do
    @moduledoc """
    Custom error for prompt-generation failures.

    The callback endpoint is a backend-to-backend integration with Kaapi (NGOs
    never interact with it), so failures are reported to AppSignal under the
    `"prompt_generator"` namespace rather than surfaced to a user. This lets us
    build an error-rate trigger on the namespace.
    """
    defexception [:message, :reason, :organization_id]

    @spec message(%__MODULE__{}) :: String.t()
    def message(%Error{} = error) do
      "#{error.message} reason: #{error.reason} organization_id: #{error.organization_id}"
    end
  end

  # AppSignal namespace for prompt-generation errors (enables a dedicated error-rate trigger).
  @appsignal_namespace "prompt_generator"

  # Per-org feature flag (BETA). Enforced server-side here in addition to the frontend
  # hiding the entry point — see Glific.Flags.init_fun_with_flags/1 where it is registered.
  @feature_flag :is_prompt_generator_enabled

  # Server-side meta-prompt — kept here so it can be tuned without frontend changes.
  @meta_prompt "You are an expert prompt engineer. Using the NGO's answers below, write a clear, production-ready SYSTEM PROMPT for a WhatsApp chatbot. Output ONLY the prompt text, ready to paste — no preamble, no markdown. Cover role & purpose, audience, language policy, tone, response length/format, off-limits topics, the exact fallback message, and the escalation path. If an answer is blank, omit that section gracefully — never invent details."

  # Per-field max length clamp (characters) to avoid overwhelming the LLM context window.
  @max_field_length 2_000

  # Ordered list of {field_atom, human label} for the 9 NGO questions.
  @answer_fields [
    {:name, "Organization Name"},
    {:purpose, "Purpose / Mission"},
    {:audience, "Target Audience"},
    {:language, "Language Policy"},
    {:tone, "Tone"},
    {:format, "Response Format"},
    {:off_limits, "Off-Limits Topics"},
    {:fallback, "Fallback Message"},
    {:escalation, "Escalation Path"}
  ]

  @doc """
  Initiates async prompt generation for the given NGO answers.

  Builds the Kaapi LLM payload (including a unique `request_id` and `callback_url`),
  calls Kaapi to obtain a `job_id`, then persists a `:in_progress`
  `PromptGenerationRequest` row. Returns `{:ok, request}` on success.

  Returns `{:error, reason}` — without inserting a row — when the per-org
  `:is_prompt_generator_enabled` feature flag is off, when Kaapi is inactive for the
  org, or when the Kaapi call itself fails.

  The feature is enforced server-side on the `:is_prompt_generator_enabled` flag (the
  frontend also hides the entry point when it is off) — frontend hiding alone is not
  sufficient for entitlement control.

  ## Parameters

    - `answers` — map with keys `:name`, `:purpose`, `:audience`, `:language`, `:tone`,
      `:format`, `:off_limits`, `:fallback`, `:escalation` (string values; blank entries
      are omitted from the LLM prompt).
    - `org_id` — organization ID (scopes the row and the Kaapi credential lookup).
    - `user_id` — optional user who initiated the request; stored for audit.

  ## Examples

      iex> Glific.PromptGenerator.generate_prompt(%{name: "Pratham", purpose: "education"}, 1)
      {:ok, %PromptGenerationRequest{status: :in_progress, ...}}
  """
  @spec generate_prompt(map(), non_neg_integer(), non_neg_integer() | nil) ::
          {:ok, PromptGenerationRequest.t()} | {:error, any()}
  def generate_prompt(answers, org_id, user_id \\ nil) do
    request_id = Ecto.UUID.generate()
    callback_url = build_callback_url(org_id)
    payload = build_llm_payload(answers, callback_url, request_id)

    with :ok <- check_feature_enabled(org_id),
         {:ok, %{job_id: job_id}} <- Kaapi.generate_prompt(payload, org_id) do
      create_request(%{
        inputs: answers,
        status: :in_progress,
        kaapi_job_id: job_id,
        organization_id: org_id,
        user_id: user_id
      })
    end
  end

  @doc """
  Handles the async callback POSTed by Kaapi after LLM completion.

  Looks up the `PromptGenerationRequest` by `kaapi_job_id`. On `"SUCCESSFUL"`,
  sets `status: :ready` and `generated_prompt`. On any other status, sets
  `status: :failed` and `error_message`. Unknown `job_id` logs and returns an error.

  This function is idempotent: calling it twice on the same row is safe — the row
  is simply re-updated to the same terminal state.

  ## Parameters

    - `data` — the parsed JSON body from Kaapi:
      ```json
      {"data": {"job_id": "...", "status": "SUCCESSFUL", "text": "...", "error_message": null}}
      ```
  """
  @spec handle_callback(map()) ::
          {:ok, PromptGenerationRequest.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def handle_callback(%{"data" => %{"job_id" => job_id} = data}) do
    with {:ok, request} <-
           Repo.fetch_by(PromptGenerationRequest, %{kaapi_job_id: job_id},
             skip_organization_id: true
           ),
         {:ok, updated} <- apply_callback(request, data) do
      {:ok, updated}
    else
      {:error, [_, "Resource not found"]} ->
        log_callback_error("No prompt generation request found for the callback",
          reason: "job_id=#{job_id}"
        )

        {:error, "Prompt generation request not found for job_id=#{job_id}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Defensive catch-all: the callback endpoint is public, so a malformed body must
  # not raise (the controller must still return 200). Kaapi sends a well-formed
  # `%{"data" => %{"job_id" => ...}}` payload; anything else is reported and ignored.
  def handle_callback(params) do
    log_callback_error("Unexpected prompt generation callback payload",
      reason: inspect(params)
    )

    {:error, "Unexpected prompt generation callback payload"}
  end

  @doc """
  Builds the Kaapi LLM API payload for prompt generation.

  The `query.input` field is the formatted answers string. The `config` blob
  specifies the OpenAI `gpt-4o` completion. The callback URL and a unique
  `request_id` (for correlation) are embedded in the envelope.

  ## Examples

      iex> Glific.PromptGenerator.build_llm_payload(%{name: "Pratham"}, "https://cb.url", "uuid-123")
      %{query: %{input: "...\n"}, config: %{...}, callback_url: "https://cb.url", ...}
  """
  @spec build_llm_payload(map(), String.t(), String.t()) :: map()
  def build_llm_payload(answers, callback_url, request_id) do
    %{
      query: %{input: format_answers(answers)},
      config: %{
        blob: %{
          completion: %{
            provider: "openai",
            type: "text",
            params: %{
              model: "gpt-4o",
              instructions: @meta_prompt,
              temperature: 0.7
            }
          }
        }
      },
      callback_url: callback_url,
      request_metadata: %{request_id: request_id}
    }
  end

  @doc """
  Formats the NGO answer map into a labelled Q→A string for the LLM.

  Blank, nil, or empty answers are omitted. Each answer is clamped to
  `#{@max_field_length}` characters to avoid context-window overflow.

  ## Examples

      iex> Glific.PromptGenerator.format_answers(%{name: "Pratham", purpose: ""})
      "Organization Name: Pratham\n"
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
        clamped = String.slice(to_string(value), 0, @max_field_length)
        acc <> "#{label}: #{clamped}\n"
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec create_request(map()) ::
          {:ok, PromptGenerationRequest.t()} | {:error, Ecto.Changeset.t()}
  defp create_request(attrs) do
    %PromptGenerationRequest{}
    |> PromptGenerationRequest.changeset(attrs)
    |> Repo.insert()
  end

  @spec apply_callback(PromptGenerationRequest.t(), map()) ::
          {:ok, PromptGenerationRequest.t()} | {:error, Ecto.Changeset.t()}
  # Terminal states are immutable: a late callback must not clobber a row that
  # already reached :ready (losing the generated prompt) or :failed.
  defp apply_callback(%PromptGenerationRequest{status: status} = request, _data)
       when status in [:ready, :failed],
       do: {:ok, request}

  defp apply_callback(request, %{"status" => "SUCCESSFUL"} = data) do
    request
    |> PromptGenerationRequest.changeset(%{
      status: :ready,
      generated_prompt: data["text"]
    })
    |> Repo.update()
  end

  defp apply_callback(request, data) do
    request
    |> PromptGenerationRequest.changeset(%{
      status: :failed,
      error_message: data["error_message"]
    })
    |> Repo.update()
  end

  @spec log_callback_error(String.t(), keyword()) :: :ok
  defp log_callback_error(message, opts) do
    Glific.log_exception(
      %Error{message: message, reason: Keyword.get(opts, :reason)},
      namespace: @appsignal_namespace
    )
  end

  @spec check_feature_enabled(non_neg_integer()) :: :ok | {:error, String.t()}
  defp check_feature_enabled(org_id) do
    if FunWithFlags.enabled?(@feature_flag, for: %{organization_id: org_id}) do
      :ok
    else
      {:error, "AI Prompt Generator is not enabled for the organization."}
    end
  end

  @spec build_callback_url(non_neg_integer()) :: String.t()
  defp build_callback_url(org_id) do
    organization = Partners.organization(org_id)
    Glific.api_callback_base(organization.shortcode) <> "/kaapi/prompt_generation"
  end

  @spec blank?(any()) :: boolean()
  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
