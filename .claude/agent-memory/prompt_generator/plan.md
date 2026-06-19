# Implementation Plan — AI-Assisted Prompt Generator (v1, Draft v1)

> Draft for engineering review. Source spec: `features/prompt-generator/v1/spec.md`.
> Research: `features/prompt-generator/v1/research.md`.

## 1. Overview

Add a **"Generate with AI (BETA)"** button next to the Instructions (Prompt) field on
Glific's Create Assistant page. It opens a 9-question modal wizard; on submit, Glific routes
the answers through the **Kaapi** LLM service, which generates a ready-to-use WhatsApp
chatbot system prompt. The result is shown in an editable preview and, on "Use this Prompt",
inserted into the existing Instructions field. Core usage funnel is instrumented via PostHog.

- **Spec (versioned):** `features/prompt-generator/v1/spec.md`
- **Top-level spec:** none (only the v1 spec exists in this repo).
- **Services affected:**
  - `glific-frontend` (React) — new modal, button, polling, PostHog events.
  - `glific` (Elixir/Absinthe) — new GraphQL mutation+query, `PromptGenerator` context,
    Kaapi LLM call, callback handler, one new table.
  - **Kaapi** (external service) — dependency: must accept a text-generation task on
    `/api/v1/llm/call` and POST a result callback. **Confirm with the Kaapi team.**

## 2. Blast Radius

> **The Dalgo `docs/domain-map.md` does not apply.** This feature is in Glific. None of the
> Dalgo entities (Source, Warehouse, Transform, Pipeline, Chart, Metric, KPI, Dashboard,
> ReportSnapshot, Share link, Notification, Alert, Org, OrgUser) are touched — the map
> traversal is a no-op. The table below is the **Glific-local** impact set.

| Surface | Hop | Why affected | Status | Notes |
|---|---|---|---|---|
| Create Assistant page (`CreateAssistant.tsx`) | 1 | Hosts the new button + modal; receives generated text into the `instructions` field | **in-scope** | Button anchored next to the existing Instructions expand icon |
| Instructions (Prompt) field | 1 | Target of "Use this Prompt" — value set via Formik `setFieldValue` | **in-scope** | Field component itself unchanged |
| New GraphQL op (`generatePrompt` mutation + `promptGeneration` query) | 1 | New API surface for kickoff + polling | **in-scope** | New types/resolver |
| `Glific.PromptGenerator` context (new) | 1 | Builds meta-prompt, calls Kaapi, persists request | **in-scope** | Server-side prompt-engineering lives here |
| `prompt_generation_requests` table (new) | 1 | Persists job → result for async callback + polling | **in-scope** | Mirrors `KnowledgeBaseVersion.kaapi_job_id` pattern |
| Kaapi callback controller + `/kaapi` route | 1 | Receives async generation result | **in-scope** | Extends `kaapi_controller.ex` |
| Kaapi `/api/v1/llm/call` (external) | 1 | Performs the actual LLM generation | **in-scope (dependency)** | Needs text-gen task support — open question Q1 |
| PostHog | 1 | Core funnel instrumentation | **in-scope** | opened / generated / applied / edited / saved |
| Assistant create/update mutations | 1 | Could have consumed generated text server-side | **out-of-scope (unaffected)** | Generated prompt is applied client-side into the existing field; these mutations are unchanged |
| Knowledge base / vector store / Assistant model | 2 | Adjacent to Instructions | **unaffected** | Generator only produces a string; no model/schema change to assistants |
| Glific server-side `Metrics` counter | 1 | Optional per-org `"Prompt Generated"` count | **deferred (nice-to-have)** | PostHog covers the funnel; add later if backend cadence is wanted |
| Per-question drop-off / time-to-complete / return-usage metrics | 1 | Listed in spec §8 (Monthly) | **deferred** | Confirmed fast-follow |
| 1–5 star feedback survey (spec §9) | 1 | Post-apply qualitative signal | **deferred** | Confirmed fast-follow |
| Multi-language UI for the question form | 1 | Spec §6 out-of-scope | **out-of-scope** | English-only form for beta |

## 3. High-Level Design (HLD)

### Architecture & data flow (async, Kaapi-routed)

```
glific-frontend (CreateAssistant page)
  │  user clicks "Generate with AI (BETA)"  → PostHog: prompt_generator_opened
  │  fills 9-question wizard, clicks "Generate Prompt"
  ▼
GraphQL mutation: generatePrompt(input: {q1..q9})        [Authorize :staff, AddOrganization]
  ▼
GlificWeb.Resolvers.PromptGenerator.generate/3
  ▼
Glific.PromptGenerator.generate_prompt(answers, org_id)
  │  1. build meta-prompt (system + formatted answers)
  │  2. Kaapi.generate_prompt(payload, org_id) → POST /api/v1/llm/call (callback_url set)
  │  3. persist prompt_generation_requests row {status: :in_progress, kaapi_job_id}
  ▼  returns { id, status: IN_PROGRESS }
frontend starts polling query: promptGeneration(id) every ~1s (startPolling/stopPolling)

   … meanwhile …
Kaapi finishes → POST /kaapi/prompt_generation  (job_id, status, generated text)
  ▼
GlificWeb.KaapiController.prompt_generation_callback
  ▼
Glific.PromptGenerator.handle_callback(params)
  │  lookup row by kaapi_job_id → write generated_prompt, status: :ready | :failed
  ▼
frontend poll returns status: READY + generatedPrompt
  │  show editable preview + review notice  → PostHog: prompt_generated
  │  "Use this Prompt" → Formik setFieldValue('instructions', text) → close modal
  │                       → PostHog: prompt_applied ; toast confirmation
  │  (on assistant save, if instructions changed since apply) → PostHog: prompt_edited
  ▼
user saves Assistant as normal (existing CREATE_ASSISTANT mutation, unchanged)
```

### New / modified API surface

| Op | Type | Auth | Purpose |
|---|---|---|---|
| `generatePrompt(input: PromptGeneratorInput!): PromptGenerationResult` | mutation | `:staff` | Kick off async generation; returns `{id, status, errors}` |
| `promptGeneration(id: ID!): PromptGeneration` | query | `:staff` | Poll for `{id, status, generatedPrompt, errorMessage}` |
| `POST /kaapi/prompt_generation` | REST webhook | shared-secret (see §5) | Kaapi delivers the result |

### Key decisions & trade-offs

- **Async (job + callback + poll), not sync.** Matches the verified Kaapi pattern
  (`/api/v1/llm/call` is async for STT/TTS) and the existing assistant-status polling on
  the frontend. Trade-off: more moving parts than a blocking call, but consistent with the
  codebase and resilient to LLM latency. Within the 2–3s UX the spec describes, ~1s polling
  is comfortable; we cap polling (~20s) and surface a friendly timeout.
- **Meta-prompt lives server-side** in `Glific.PromptGenerator`. Tunable without a frontend
  release; not exposed to clients; central place to iterate prompt quality during beta.
- **Assistant write path untouched.** Generated text is applied client-side to the existing
  `instructions` field, so no change to `create/update_assistant`. Lowest-risk integration.
- **Partial answers allowed** (spec §7): no required fields; the meta-prompt instructs the
  LLM to gracefully omit sections the user left blank.

## 4. Low-Level Design (LLD)

### 4.1 Data model (`glific`)

New migration + schema `prompt_generation_requests`:

```elixir
# priv/repo/migrations/XXXXXXXX_create_prompt_generation_requests.exs
create table(:prompt_generation_requests) do
  add :inputs, :map, null: false            # the 9 answers, keyed q1..q9
  add :generated_prompt, :text              # nil until :ready
  add :status, :string, null: false, default: "in_progress"  # in_progress|ready|failed
  add :kaapi_job_id, :string                # callback lookup key
  add :error_message, :text
  add :organization_id, references(:organizations, on_delete: :delete_all), null: false
  add :user_id, references(:users, on_delete: :nilify_all)
  timestamps(type: :utc_datetime)
end
create unique_index(:prompt_generation_requests, [:kaapi_job_id])
create index(:prompt_generation_requests, [:organization_id])
```

Schema module `lib/glific/prompt_generator/prompt_generation_request.ex` with an
`Ecto.Enum` status `[:in_progress, :ready, :failed]`, `belongs_to :organization`,
`belongs_to :user`. Follow the `KnowledgeBaseVersion` schema for conventions.

> **Retention note (PII):** `inputs` may contain an org name and an escalation phone/email
> (Q1, Q9). Store only what's needed; add a scheduled purge (e.g. delete rows > 30 days) or
> drop `inputs` once `status = :ready`. Decide in review (Q4).

### 4.2 Backend logic (`glific`)

`lib/glific/prompt_generator.ex` (context):

```elixir
@questions ~w(name purpose audience language tone format off_limits fallback escalation)a

def generate_prompt(answers, org_id, user_id \\ nil) do
  with {:ok, _creds}   <- Kaapi.fetch_kaapi_creds(org_id),     # fail fast if Kaapi inactive
       payload          = build_llm_payload(answers),           # meta-prompt + callback_url
       {:ok, %{job_id: job_id}} <- Kaapi.generate_prompt(payload, org_id),
       {:ok, request}  <- create_request(answers, org_id, user_id, job_id) do
    {:ok, request}                                              # status: :in_progress
  end
end

def handle_callback(%{"data" => %{"job_id" => job_id} = data}) do
  with {:ok, req} <- Repo.fetch_by(PromptGenerationRequest, %{kaapi_job_id: job_id}) do
    case data["status"] do
      "SUCCESSFUL" -> update_request(req, %{status: :ready,  generated_prompt: data["text"]})
      _            -> update_request(req, %{status: :failed, error_message: data["error_message"]})
    end
  end
end

defp build_llm_payload(answers, callback_url, request_id) do
  # Mirrors the real Kaapi /api/v1/llm/call envelope (see tts_payload / build_config_blob
  # in lib/glific/third_party/kaapi.ex). Two distinct slots:
  #   - params.instructions = OUR meta-prompt ("what to do")
  #   - query.input         = the 9 formatted answers ("the data")
  %{
    query: %{input: format_answers(answers)},      # labelled Q→A, blanks omitted
    config: %{blob: %{completion: %{
      provider: "openai",
      type: "text",                                # vs "stt"/"tts" today — confirm with Kaapi (Q1)
      params: %{
        model: "gpt-4o",
        instructions: @meta_prompt,                # server-side, tunable without a frontend release
        temperature: 0.7
      }
    }}},
    callback_url: callback_url,                     # GlificWeb …/kaapi/prompt_generation
    request_metadata: %{request_id: request_id}     # echoed back → match the prompt_generation row
  }
end

# @meta_prompt: "You are an expert prompt engineer. Using the NGO's answers below, write a
# clear, production-ready SYSTEM PROMPT for a WhatsApp chatbot. Output ONLY the prompt text,
# ready to paste — no preamble, no markdown. Cover role & purpose, audience, language policy,
# tone, response length/format, off-limits topics, the exact fallback message, and the
# escalation path. If an answer is blank, omit that section gracefully — never invent details."
```

Add `Kaapi.generate_prompt/2` in `lib/glific/third_party/kaapi.ex` + the corresponding
`ApiClient` call to `POST /api/v1/llm/call` (mirror `speech_to_text/5`).

### 4.3 GraphQL (`glific`)

New `lib/glific_web/schema/prompt_generator_types.ex`:

```elixir
input_object :prompt_generator_input do
  field :name, :string;       field :purpose, :string;   field :audience, :string
  field :language, :string;   field :tone, :string;      field :format, :string
  field :off_limits, :string; field :fallback, :string;  field :escalation, :string
end

object :prompt_generation do
  field :id, :id
  field :status, :string                 # in_progress | ready | failed
  field :generated_prompt, :string
  field :error_message, :string
end

object :prompt_generation_result do
  field :prompt_generation, :prompt_generation
  field :errors, list_of(:input_error)
end

object :prompt_generator_mutations do
  field :generate_prompt, :prompt_generation_result do
    arg(:input, non_null(:prompt_generator_input))
    middleware(Authorize, :staff)
    resolve(&Resolvers.PromptGenerator.generate/3)
  end
end

object :prompt_generator_queries do
  field :prompt_generation, :prompt_generation do
    arg(:id, non_null(:id))
    middleware(Authorize, :staff)
    resolve(&Resolvers.PromptGenerator.get/3)
  end
end
```

Wire `import_fields` into `schema.ex`. Resolver
`lib/glific_web/resolvers/prompt_generator.ex` reads `org_id` from
`%{context: %{current_user: user}}` and **scopes the poll query to the caller's org**
(reject cross-org `id`). Callback controller fn in `kaapi_controller.ex` + route in the
existing `scope "/kaapi"` block.

### 4.4 Frontend components (`glific-frontend`)

- **`graphql/mutations/PromptGenerator.ts`** — `GENERATE_PROMPT`.
  **`graphql/queries/PromptGenerator.ts`** — `PROMPT_GENERATION` (polled).
- **`containers/Assistants/PromptGenerator/PromptGeneratorModal.tsx`** (new):
  - Trigger: `Button` labelled "Generate with AI" + a `BETA` badge, placed next to the
    Instructions field in `CreateAssistant.tsx` (near the existing expand icon ~205–255).
  - Wizard: 9 steps (or a single scrollable form) with **examples** and a **progress bar**;
    no required fields. Reuse `Input` / `AutoComplete`. Q4 (Language) and Q5 (Tone) are
    good `AutoComplete` candidates with an "other" free-text.
  - "Generate Prompt" → `useMutation(GENERATE_PROMPT)` → on success start
    `useLazyQuery(PROMPT_GENERATION, { fetchPolicy: 'network-only' })` with
    `startPolling(1000)`; show loading state. On `READY` `stopPolling()` and render the
    editable `OutlinedInput`/textarea preview + review notice:
    *"This is an AI generated prompt. Please review and edit if required."*
  - "Use this Prompt" → `formik.setFieldValue('instructions', editedText)`, close modal,
    `setNotification('Prompt added to Instructions', 'success')`.
  - Errors / timeout (>~20s, or `failed`, or Kaapi inactive) → friendly message + retry,
    via `setErrorMessage`.
- **CreateAssistant.tsx**: render the trigger; pass `formik` (or a callback) so the modal
  can set `instructions`; track whether the applied prompt is later edited (compare on
  submit) to emit `prompt_edited`.

### 4.5 Integration points

- Frontend → backend: Apollo `useMutation` / polled `useLazyQuery` (Absinthe).
- Backend → Kaapi: Tesla `POST /api/v1/llm/call` with `X-API-KEY` (per-org creds via
  `Kaapi.fetch_kaapi_creds/1`), `callback_url` pointing at `/kaapi/prompt_generation`.
- Kaapi → backend: REST webhook → `PromptGenerator.handle_callback/1` → DB update → next
  frontend poll observes `READY`.

## 5. Security Review

- **AuthN/Z:** Both GraphQL ops require `middleware(Authorize, :staff)` (same bar as
  Assistant ops). `ContextPlug` supplies `current_user`; no anonymous access.
- **Multi-tenant isolation:** `generatePrompt` stamps `organization_id` from the context
  (never from client input). `promptGeneration(id)` **must filter by the caller's
  `organization_id`** so a user cannot poll another org's request — explicit `Repo.fetch_by`
  with `organization_id` guard; return not-found on mismatch. Add a test for cross-org read.
- **Input validation:** All 9 fields are optional strings. Enforce a **max length per field**
  (e.g. 1–2k chars) and a total cap at the Absinthe input boundary to bound LLM token cost
  and block oversized payloads. Reject non-string types (schema does this).
- **Prompt injection / output safety:** User answers are interpolated into an LLM prompt.
  The generated text is **only ever placed into the Instructions field for the user to
  review** — it is not executed and not auto-saved. Keep the meta-prompt server-side; do not
  echo raw answers into logs at info level (may contain org PII).
- **Sensitive data:** Q1 (org name) and Q9 (escalation phone/email) are mild PII. Stored in
  `inputs`; transmitted to Kaapi over TLS. See retention note (§4.1 / Q4). Kaapi API key is a
  per-org secret in `organization.services["kaapi"].secrets` — never sent to the client.
- **Webhook security:** `/kaapi/prompt_generation` is unauthenticated by default like other
  Kaapi callbacks. Confirm how the existing KB callback is protected (shared secret / IP
  allowlist) and apply the same; at minimum, treat `job_id` as an unguessable token and
  validate the row exists + is still `:in_progress` before applying (idempotent). (Q2)
- **Rate limiting / abuse:** The op rides the global ExRated per-user limit. Because each
  call costs an LLM round-trip, add a **tighter per-user/org throttle** (e.g. N
  generations/min) to cap spend. (Q3)
- **External call hardening:** Validate Kaapi responses before use (presence of `job_id`;
  callback `status`/`text` shape). Fail closed: if Kaapi is inactive for the org, return a
  clear error and never block the rest of the assistant form.

## 6. Testing Strategy

### Unit — `glific` (ExUnit, `Tesla.Mock`)
- `PromptGenerator.build_llm_payload/1`: blanks omitted; all-9 formatting; max-length clamp.
- `generate_prompt/3`: happy path persists `:in_progress` + `kaapi_job_id`; Kaapi-inactive
  org → error; Kaapi 4xx/5xx → error, no row leaked.
- `handle_callback/1`: `SUCCESSFUL` → `:ready` + text; failure → `:failed` + message;
  unknown `job_id` → no-op; double callback is idempotent.

### Integration — `glific` (Wormwood GraphQL)
- `generatePrompt` mutation as `:staff` → `IN_PROGRESS`; as unauthorized → rejected.
- `promptGeneration(id)` returns own-org row; **cross-org id → not found** (tenancy test).
- Full async loop: mutation → simulate callback → query returns `READY` + prompt (mirror
  `assistants_test.exs` KB-callback test ~1970–2034).

### Frontend — `glific-frontend` (Vitest + MockedProvider)
- Button renders with BETA badge next to Instructions.
- Wizard: progress bar advances; partial submit allowed (no required-field block).
- Mocked `GENERATE_PROMPT` → polled `PROMPT_GENERATION` (in_progress → ready) → preview
  shows; edit then "Use this Prompt" sets `instructions` (assert Formik value) + toast.
- Error/timeout path renders retry.
- PostHog: assert `posthog.capture` called for opened/generated/applied/edited (spy).

### Edge cases
- All fields blank (still generates a generic-but-valid prompt).
- Kaapi never calls back → frontend polling timeout → friendly error, modal stays open.
- User edits preview before applying (counts as applied, not a regeneration).
- User closes modal mid-generation (stop polling; no crash).
- Org without Kaapi onboarded → button visible but generation returns a clear error
  (decide in review whether to hide the button instead — Q5).

### Test data
- Fixture sets of 9 answers (full / partial / empty). Mocked Kaapi job-id + callback bodies.

## 7. Milestones

#### Milestone 1: Backend — generation engine (no UI)
- **Deliverable:** `Glific.PromptGenerator` context + `prompt_generation_requests` table +
  `Kaapi.generate_prompt/2` + callback handler. Fully unit-tested with `Tesla.Mock`. No
  GraphQL, no UI — internal API only.
- **Services:** `glific`.
- **Key tasks:**
  - [ ] Migration + schema for `prompt_generation_requests` (status enum, indexes).
  - [ ] `Kaapi.generate_prompt/2` + `ApiClient` `POST /api/v1/llm/call` wrapper.
  - [ ] `PromptGenerator.generate_prompt/3`, `handle_callback/1`, `build_llm_payload/1`.
  - [ ] Unit tests: payload building, happy/error paths, callback lifecycle, idempotency.
- **Acceptance:** `mix test` green; calling `generate_prompt/3` (mocked Kaapi) persists an
  `:in_progress` row; a simulated callback flips it to `:ready` with text.

#### Milestone 2: Backend — GraphQL surface + webhook
- **Deliverable:** `generatePrompt` mutation, `promptGeneration` query, `/kaapi/prompt_generation`
  callback route, auth + tenancy enforced.
- **Services:** `glific`.
- **Key tasks:**
  - [ ] `prompt_generator_types.ex` (input/object/result) + wire into `schema.ex`.
  - [ ] `Resolvers.PromptGenerator.generate/3` + `get/3` (org-scoped poll).
  - [ ] Callback controller fn + route in `scope "/kaapi"`.
  - [ ] Per-user/org throttle for generation (Q3); input max-length validation.
  - [ ] GraphQL tests incl. cross-org isolation.
- **Acceptance:** From GraphQL playground, `:staff` user runs the full mutation→callback→query
  loop and gets a generated prompt; cross-org poll returns not-found; non-staff rejected.

#### Milestone 3: Frontend — modal, wizard, apply-to-field
- **Deliverable:** "Generate with AI (BETA)" button + 9-question wizard + polling + editable
  preview + review notice + "Use this Prompt" → Instructions field + confirmation toast.
- **Services:** `glific-frontend`.
- **Key tasks:**
  - [ ] `GENERATE_PROMPT` mutation + polled `PROMPT_GENERATION` query.
  - [ ] `PromptGeneratorModal.tsx` (steps, progress bar, examples, partial-answers).
  - [ ] Loading + error/timeout states; apply via `formik.setFieldValue('instructions', …)`.
  - [ ] Button + BETA badge in `CreateAssistant.tsx`; Vitest tests (MockedProvider).
- **Acceptance:** On the Create Assistant page, a user generates a prompt end-to-end and the
  text lands in Instructions; the assistant then saves normally (unchanged save path).
  Run `/design-review` on the modal before sign-off.

#### Milestone 4: Frontend — PostHog core-funnel instrumentation
- **Deliverable:** `posthog.capture` for `prompt_generator_opened`, `prompt_generated`,
  `prompt_applied`, `prompt_edited`, and the existing assistant-save mapped to a funnel.
- **Services:** `glific-frontend`.
- **Key tasks:**
  - [ ] Fire events at trigger, on `READY`, on apply, on edit-before-save.
  - [ ] Include props (e.g. `answers_filled_count`) where cheap; **no PII** in event props.
  - [ ] Spec/test the capture calls.
- **Acceptance:** Events appear in PostHog dev with correct names/props. Should land **with**
  M3 before public beta (spec §8: "instrumented from day one"); kept separate for review.

> Deferred fast-follow (not in v1): per-question drop-off, time-to-complete, return-usage,
> 1–5 star survey (spec §9), and an optional server-side `Metrics.increment("Prompt
> Generated", org_id)`.

## 8. Open Questions & Risks

- **Q1 (blocking dependency):** Does Kaapi's `/api/v1/llm/call` accept a
  `config.blob.completion.type: "text"` task (with `params.instructions` = our meta-prompt
  and `query.input` = the answers) and POST the **generated text** back via `callback_url`?
  Today the endpoint is exercised for `type: "stt"`/`"tts"`; a `type: "text"` shape already
  exists in `build_config_blob` (assistant config), which is encouraging but not the same
  code path. If unsupported, Kaapi needs a small addition (or we fall back to a direct OpenAI
  call — not the chosen path). **Owner: Kaapi team.** This gates M1.
- **Q2:** How is the existing Kaapi KB callback authenticated (shared secret / IP allowlist)?
  Apply the same to `/kaapi/prompt_generation`.
- **Q3:** Desired throttle for generations (per user? per org? requests/min)? Drives cost.
- **Q4:** Retention for `inputs` (org name + escalation contact are mild PII) — purge after
  `:ready`? after 30 days? Keep for metrics analysis?
- **Q5:** For orgs **not** onboarded to Kaapi — hide the button, or show it and return a
  clear "not available" error on generate?
- **Risk — latency/timeout:** LLM + async hop may exceed the spec's "2–3s". Mitigate with a
  clear loading state and a ~20s polling cap with a friendly timeout + retry.
- **Risk — prompt quality:** Beta meta-prompt may produce weak prompts for sparse answers.
  Mitigated by server-side meta-prompt (tunable without release) and the deferred 1–5 star
  survey to gather signal.
- **Risk — cost:** Each click is an LLM call; throttle (Q3) and the per-field/total length
  caps bound spend.
- **Dependency:** Kaapi must be reachable and onboarded per org; reuse `fetch_kaapi_creds/1`
  fail-fast.

---

Draft v1 saved. Review the plan and tell me what to revise — architecture, scope, milestones, anything. When ready, run `/engineering/execute-plan features/prompt-generator/v1/plan.md` to implement.
