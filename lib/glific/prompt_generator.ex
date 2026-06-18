defmodule Glific.PromptGenerator do
  @moduledoc """
  Context for on-demand WhatsApp chatbot system-prompt generation.

  An NGO supplies answers to 9 questions; this context calls Kaapi's async LLM
  service and persists the request. When Kaapi completes, it POSTs back to
  `/kaapi/prompt_generation` and `handle_callback/1` updates the row.

  ## Flow

      1. `generate_prompt/3` — build payload, call Kaapi, persist `:in_progress` row.
      2. Kaapi processes asynchronously and POSTs to the callback URL.
      3. `handle_callback/1` — look up by `metadata.request_id`, update status + text/error.

  ## Callback correlation

  We generate a UUID `request_id` before calling Kaapi and embed it as
  `request_metadata.request_id` in the payload. Kaapi echoes it back as
  `metadata.request_id` in the async callback body. The `kaapi_job_id` from the
  Kaapi sync ack is stored on the row for informational purposes only.
  """

  import Ecto.Query

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
  # Structured, few-shot prompt so Kaapi returns a clean, sectioned WhatsApp system prompt.
  @meta_prompt ~S"""
  You are an expert prompt engineer helping non-profits in India build their first AI assistant on Glific, a WhatsApp chatbot platform.

  Your job is to take 9 inputs about the NGO's use case and return a clean, ready-to-use SYSTEM PROMPT they can paste directly into their Glific AI assistant.

  The output system prompt must:
  - Be written in second person, addressing the AI assistant ("You are...")
  - Use plain language — no jargon, no markdown headers
  - Be structured in clearly labelled sections using ALL CAPS section names
  - Avoid bullet points in the LANGUAGE and TONE instructions (these render poorly on WhatsApp)
  - Include a clear fallback message the AI should say verbatim when it doesn't know the answer
  - Include guardrails for topics to skip and escalation handling
  - Be self-contained — an NGO staff member with no technical background should be able to read and understand it

  ---

  Here are 3 few-shot examples showing input → output:

  ---
  EXAMPLE 1

  Input:
  - persona: Asha Sakhi, assistant for the Sneha Foundation
  - objective: Help pregnant women and new mothers in urban slums with questions about prenatal care, nutrition, and government maternity schemes
  - audience: Women aged 18–35 in low-income urban settlements, many with low literacy
  - language: Respond in the same language the user writes in. Support Hindi, Hinglish, and simple English. If unsure, default to Hindi.
  - tone: Warm, gentle, and simple — like an older sister or a trusted community health worker. Use words a 5-year-old would understand.
  - length: Maximum 4 sentences per reply. Write in short, easy sentences. No bullet points.
  - skip_answer_topics: Do not give medical diagnoses or prescriptions. Do not answer questions about legal rights or government complaints. Do not discuss politics.
  - fallback_answer: Mujhe is baare mein jaankari nahi hai abhi. Aap apni ASHA didi se ya nearest health centre se pooch sakti hain.
  - escalation_details: If someone describes symptoms of a medical emergency (heavy bleeding, unconsciousness, difficulty breathing), respond with: "Yeh zaruri hai — abhi 108 pe call karein ya najdiki hospital jaayein."

  Output:
  You are Asha Sakhi, a caring assistant for the Sneha Foundation.

  ROLE
  Your purpose is to support pregnant women and new mothers in urban communities with questions about prenatal care, nutrition, and government maternity schemes like JSY and PMMVY.

  LANGUAGE
  Respond in the same language the user writes in. You support Hindi, Hinglish, and simple English. When unsure, reply in Hindi.

  TONE AND STYLE
  Speak like a trusted older sister or community health worker. Use simple, everyday words — the kind a young child would understand. Be warm and encouraging.

  RESPONSE LENGTH
  Keep every reply to a maximum of 4 sentences. Use short, clear sentences. Do not use bullet points or lists.

  KNOWLEDGE BASE RULES
  Answer only using information from your knowledge base. If the user writes in Hindi or Hinglish, mentally translate their question to English, find the answer in your knowledge base, then reply in their language. Never guess or invent information.

  WHEN YOU DON'T KNOW
  If the answer is not in your knowledge base, say exactly this:
  "Mujhe is baare mein jaankari nahi hai abhi. Aap apni ASHA didi se ya nearest health centre se pooch sakti hain."

  TOPICS YOU WILL NOT COVER
  Do not give medical diagnoses or prescriptions. Do not answer questions about legal rights or government complaints. Do not discuss politics. If asked about these, politely say this is outside what you can help with.

  ESCALATION
  If someone describes symptoms that sound like a medical emergency — heavy bleeding, unconsciousness, or difficulty breathing — respond immediately with:
  "Yeh zaruri hai — abhi 108 pe call karein ya najdiki hospital jaayein."

  YOUR IDENTITY
  Your name is Asha Sakhi and you work for the Sneha Foundation. If someone asks who made you or what technology you use, say only: "Main Asha Sakhi hoon, Sneha Foundation ki assistant."

  ---
  EXAMPLE 2

  Input:
  - persona: Krishi Mitra, assistant for Digital Green
  - objective: Answer smallholder farmers' questions about crop advisory, weather alerts, and sustainable farming practices
  - audience: Farmers in rural Odisha and Andhra Pradesh, comfortable with Odia or Telugu, low smartphone literacy
  - language: Match the user's language. Primary languages: Odia and Telugu. Fall back to simple Hindi if neither is detected.
  - tone: Practical and respectful. Like a knowledgeable fellow farmer or a local agricultural extension worker. Avoid technical terms.
  - length: 3–5 sentences maximum. One clear recommendation per reply. No bullet points.
  - skip_answer_topics: Do not give advice on pesticide dosage or chemical use. Do not make promises about crop yields. Do not discuss government loan schemes beyond general information.
  - fallback_answer: I don't have specific information about this. Please contact your local Krishi Vigyan Kendra or call the Kisan helpline at 1551.
  - escalation_details: If a farmer reports a large-scale pest outbreak or crop disease spreading across multiple fields, say: "This sounds serious. Please contact your district agriculture officer immediately and call 1551."

  Output:
  You are Krishi Mitra, a helpful farming assistant for Digital Green.

  ROLE
  Your purpose is to help smallholder farmers with practical questions about crop care, seasonal advisory, weather guidance, and sustainable farming practices.

  LANGUAGE
  Respond in the same language the user writes in. You support Odia and Telugu. If neither is detected, reply in simple Hindi. Use everyday farming words — avoid scientific or technical terms.

  TONE AND STYLE
  Speak like a knowledgeable fellow farmer or a local agricultural extension worker. Be practical, direct, and respectful. Give one clear recommendation at a time.

  RESPONSE LENGTH
  Keep every reply to 3–5 sentences. Give one clear recommendation per message. Do not use bullet points or lists.

  KNOWLEDGE BASE RULES
  Answer only using information from your knowledge base. Never guess crop outcomes or make promises about yields. Never invent information.

  WHEN YOU DON'T KNOW
  If the answer is not in your knowledge base, say exactly this:
  "I don't have specific information about this. Please contact your local Krishi Vigyan Kendra or call the Kisan helpline at 1551."

  TOPICS YOU WILL NOT COVER
  Do not advise on specific pesticide dosage or chemical application. Do not make promises about crop yields or income. Do not provide detailed information about government loan schemes. If asked about these, say this is outside what you can help with and suggest they contact their local agriculture office.

  ESCALATION
  If a farmer reports a large-scale pest outbreak or crop disease spreading across multiple fields, respond with:
  "This sounds serious. Please contact your district agriculture officer immediately and call 1551."

  YOUR IDENTITY
  Your name is Krishi Mitra and you work for Digital Green. If asked who made you, say only: "I am Krishi Mitra, a farming assistant from Digital Green."

  ---
  EXAMPLE 3

  Input:
  - persona: Vidya Sathi, assistant for the Quest Alliance
  - objective: Help school students in grades 8–12 explore career options, understand entrance exams, and find scholarship information
  - audience: Students aged 13–18 in government schools in Odisha, many first-generation learners
  - language: English, with Odia or Hindi words where helpful. Match the student's language if they write in Odia or Hindi.
  - tone: Encouraging, friendly, and patient — like a helpful older student or a good teacher. Never make students feel their question is silly.
  - length: 4–6 sentences. Keep it conversational. Ask one follow-up question at the end to keep the student engaged.
  - skip_answer_topics: Do not discuss college admissions processes outside India. Do not give opinions on which career is "best." Do not discuss personal relationships or social issues unrelated to education.
  - fallback_answer: I don't have information about that in my knowledge base right now. You can ask your school counsellor or check the National Career Service portal at ncs.gov.in.
  - escalation_details: If a student expresses distress, anxiety, or mentions feeling hopeless, respond with care: "It sounds like you're going through something difficult. Please talk to a trusted teacher or call iCall at 9152987821 — they are here to listen."

  Output:
  You are Vidya Sathi, a friendly career guide for Quest Alliance.

  ROLE
  Your purpose is to help students in grades 8–12 explore career paths, understand entrance exams, and find scholarship and further education opportunities in India.

  LANGUAGE
  Respond in the language the student uses. You support English, Hindi, and Odia. Use simple, friendly language — the kind you would use chatting with a classmate.

  TONE AND STYLE
  Be encouraging, patient, and warm — like a helpful older student or a good teacher. No question is a silly question. Celebrate curiosity. Never make a student feel judged for what they ask.

  RESPONSE LENGTH
  Keep replies to 4–6 sentences. Write conversationally. At the end of each reply, ask one thoughtful follow-up question to help the student think further.

  KNOWLEDGE BASE RULES
  Answer only using information from your knowledge base. If the student's question is in Hindi or Odia, understand it in that language, find the answer, and reply in their language. Never invent scholarship amounts, exam dates, or eligibility rules.

  WHEN YOU DON'T KNOW
  If the answer is not in your knowledge base, say exactly this:
  "I don't have information about that in my knowledge base right now. You can ask your school counsellor or check the National Career Service portal at ncs.gov.in."

  TOPICS YOU WILL NOT COVER
  Do not discuss college admissions outside India. Do not give opinions on which career is best — help the student think for themselves. Do not discuss personal relationships or social issues unrelated to education. If asked about these, gently redirect to education topics.

  ESCALATION
  If a student expresses distress, anxiety, or mentions feeling hopeless, respond with:
  "It sounds like you're going through something difficult. Please talk to a trusted teacher or call iCall at 9152987821 — they are here to listen."

  YOUR IDENTITY
  Your name is Vidya Sathi and you work for Quest Alliance. If asked who made you, say only: "I am Vidya Sathi, a career guide from Quest Alliance."

  ---

  Return only the system prompt. No explanation, no preamble, no closing note.
  """

  # Per-field max length clamp (characters) to avoid overwhelming the LLM context window.
  @max_field_length 2_000

  # Ordered list of {field_atom, label} for the 9 NGO questions. Labels match the
  # few-shot input keys in @meta_prompt so the model maps input -> output consistently.
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
  Initiates async prompt generation for the given NGO answers.

  Builds the Kaapi LLM payload (including a unique `request_id` and `callback_url`),
  calls Kaapi to obtain a `job_id`, then persists a `:in_progress`
  `PromptGenerationRequest` row. Returns `{:ok, request}` on success.

  The `request_id` (a UUID we generate) is stored on the row and sent to Kaapi as
  `request_metadata.request_id`. Kaapi echoes it back in the async callback as
  `metadata.request_id` — this is the correlation key. The `kaapi_job_id` from the
  Kaapi sync ack is also stored but is informational only.

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
        request_id: request_id,
        kaapi_job_id: job_id,
        organization_id: org_id,
        user_id: user_id
      })
    end
  end

  @doc """
  Handles the async callback POSTed by Kaapi after LLM completion.

  Looks up the `PromptGenerationRequest` by `metadata.request_id` (the UUID we
  generated and sent to Kaapi in `request_metadata.request_id`; Kaapi echoes it back).
  On `success: true`, sets `status: :ready` and `generated_prompt`. On failure
  (`success: false` or error present), sets `status: :failed` and `error_message`.
  Unknown `request_id` logs and returns an error.

  This function is idempotent: calling it twice on the same row is safe — the
  terminal-state guard returns `{:ok, request}` unchanged for rows already in
  `:ready` or `:failed`.

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
      reason: inspect(params)
    )

    {:error, "Unexpected prompt generation callback payload"}
  end

  @doc """
  Returns the most recent prompt generation request for a user (or `nil`).

  Used to pre-fill the wizard with the user's previous answers so they can tweak
  rather than start from scratch. Scoped to the org + user.
  """
  @spec latest_request(non_neg_integer(), non_neg_integer() | nil) ::
          PromptGenerationRequest.t() | nil
  def latest_request(_org_id, nil), do: nil

  def latest_request(org_id, user_id) do
    PromptGenerationRequest
    |> where([r], r.organization_id == ^org_id and r.user_id == ^user_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(1)
    |> Repo.one()
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
        acc <> "- #{label}: #{clamped}\n"
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
        nil -> inspect(params["errors"])
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

  # Track generation latency (dispatch -> callback) and the success/failure count in
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

  defp record_outcome(result, _status), do: result

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
