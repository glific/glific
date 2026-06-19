# Research — AI-Assisted Prompt Generator (v1)

> Source spec: `features/prompt-generator/v1/spec.md`
> Date: 2026-06-16

## 0. Important framing: this is a Glific feature, not a Dalgo feature

The spec describes Glific's **Create Assistant** page (WhatsApp AI chatbots). The code
lives in two repos, **not** the Dalgo repos referenced by `dalgo-core/CLAUDE.md`:

- `glific` — Elixir / Phoenix / Absinthe GraphQL backend (`/Users/amishabisht/projects/glific`)
- `glific-frontend` — React + TypeScript + Apollo + MUI + Formik (`/Users/amishabisht/projects/glific-frontend`)

Consequence: the Dalgo `docs/domain-map.md` entities (Chart, Dashboard, Metric, KPI,
ReportSnapshot, …) are **not in the impact set**. The domain-map traversal is a no-op
here. The Blast Radius in `plan.md` is built from the Glific surfaces instead.

## 1. Confirmed scope decisions (from user, Pre-Check)

- **Generation engine:** LLM **via the Kaapi service** (not client-side templating, not a
  direct OpenAI call from the Elixir app). Reuses the existing async Assistant/Kaapi infra.
- **Metrics:** Core funnel via **PostHog** (opened / generated / applied / edited / saved).
  Per-question drop-off, time-to-complete, return-usage, and the 1–5 star survey are
  **deferred** to a fast-follow.

## 2. Frontend findings (`glific-frontend`)

### Create Assistant page & the Instructions field
- Page: `src/containers/Assistants/CreateAssistant/CreateAssistant.tsx`
  - Form library: **Formik** + **Yup** (`FormSchema`, lines ~81–86).
  - Fields built from a `formFields` array rendered via `<Field {...field} />` inside a
    `<FormikProvider>` (lines ~458–468).
  - **Instructions field** = `name: 'instructions'`, an `Input` with `textArea: true`,
    `rows: 3`, label `"Instructions (Prompt)*"` (lines ~246–255). It already has an
    `endAdornment` **expand icon** that opens a full-screen MUI `Modal` with an
    `OutlinedInput` (lines ~205–207, ~374–399). This is the natural anchor for the new
    "Generate with AI (BETA)" button.
- Payload to backend (lines ~89–102): `{ instructions, model, name, temperature,
  description, knowledgeBaseVersionId }`. The generated prompt simply lands in
  `instructions` — **the create/update assistant mutations are unchanged.**

### Reusable building blocks
- Dialog: `src/components/UI/DialogBox/DialogBox.tsx` (MUI Dialog wrapper; `open`, `title`,
  `handleOk`, `handleCancel`, `buttonOkLoading`, `disableOk`, `fullWidth`).
- Input: `src/components/UI/Form/Input/Input.tsx` (text / textarea).
- AutoComplete (select): `src/components/UI/Form/AutoComplete/AutoComplete.tsx`.
- Button with spinner: `src/components/UI/Form/Button/Button.tsx` (`loading` prop).
- Loading: `src/components/UI/Layout/Loading/Loading.tsx` (`CircularProgress`).
- Notifications: `src/common/notification.ts` — `setNotification(msg, 'success')`,
  `setErrorMessage(err)` (write to Apollo cache; rendered by a global Notification comp).

### GraphQL layer (Apollo)
- Client: `src/config/apolloclient.ts` (apollo-absinthe-upload-link, retry, token refresh).
- Assistant mutations: `src/graphql/mutations/Assistant.ts` (`CREATE_ASSISTANT`,
  `UPDATE_ASSISTANT`). Queries: `src/graphql/queries/Assistant.ts` (`GET_ASSISTANT`).
- **Polling precedent:** `GET_ASSISTANT` is used with `useLazyQuery(..., { fetchPolicy:
  'network-only' })` plus `startPolling` / `stopPolling` to watch async status — exactly
  the pattern we need for prompt-generation polling.

### Analytics
- **PostHog** is wired: `src/index.tsx` (`initPostHog`), `src/services/PostHogService.ts`,
  `usePostHog()` hook → `posthog.capture('event', { props })`.
- Secondary `src/services/TrackService.tsx` (`Track(event)` → `USER_TRACKER`).

### Testing
- **Vitest** + `@testing-library/react`. GraphQL mocked with `@apollo/client/testing`
  `MockedProvider`. Existing mocks: `src/mocks/Assistants.ts`. Example test:
  `src/containers/Assistants/AssistantOptions/AssistantOptions.test.tsx`.

## 3. Backend findings (`glific`)

### Assistant model & prompt storage
- `lib/glific/assistants/assistant.ex`, `lib/glific/assistants/assistant_config_version.ex`
  (`prompt: String.t()` holds the system prompt), context `lib/glific/assistants.ex`.
- The generator does **not** touch these — it only produces a string the user pastes into
  the Instructions field client-side.

### Kaapi integration (the chosen engine)
- Module: `lib/glific/third_party/kaapi.ex`; HTTP client:
  `lib/glific/third_party/kaapi/api_client.ex` (Tesla).
- Config: base URL `kaapi_endpoint`, key `kaapi_api_key` (`config/runtime.exs` ~186–187).
- Per-org creds: `Kaapi.fetch_kaapi_creds/1` → `organization.services["kaapi"].secrets`
  (returns `{:error, "Kaapi is not active"}` when the org isn't onboarded). Auth header
  `X-API-KEY`.
- **Unified LLM endpoint:** `POST /api/v1/llm/call` (api_client.ex ~81) — currently used by
  `speech_to_text/5` and `text_to_speech/5`. It is **asynchronous**: returns a `job_id` /
  `status: queued`, then Kaapi POSTs a **callback** to a Glific webhook with the result.
  This is the path a text-generation call would follow.
- **Async result pattern (verified via KB creation):**
  1. Glific calls Kaapi, gets `job_id`, persists a record with `kaapi_job_id` and
     `status: :in_progress`.
  2. Kaapi POSTs to a callback controller:
     `lib/glific_web/controllers/kaapi_controller.ex` →
     route `scope "/kaapi"` in `lib/glific_web/router.ex` (~128–132).
  3. Handler looks up the record by `kaapi_job_id`, writes the result + flips status to
     `:ready` / `:failed` (`Assistants.handle_knowledge_base_callback/1`, assistants.ex
     ~1087–1123).
  4. Frontend polls a GraphQL query for the status/result.
- **Open dependency:** confirm with the Kaapi team that `/api/v1/llm/call` supports a plain
  **text/chat completion** task type (today it is exercised for STT/TTS). If not, Kaapi
  needs a small addition, or we fall back to a direct OpenAI call (not the chosen path).

### GraphQL (Absinthe) wiring pattern
- Schema: `lib/glific_web/schema.ex`; types e.g. `lib/glific_web/schema/assistant_types.ex`;
  resolvers `lib/glific_web/resolvers/filesearch.ex`.
- End-to-end: `field … do arg(:input, …); middleware(Authorize, :staff);
  resolve(&Resolvers.Filesearch.fn/3) end` → resolver → context module.
- Auth/tenancy: `ContextPlug` injects `current_user` (with `organization_id`, `roles`);
  `Authorize` middleware enforces role (`:staff` used for Assistant ops); `AddOrganization`
  middleware injects `organization_id` into args automatically.
- Rate limiting: `lib/glific_web/plugs/rate_limit_plug.ex` (ExRated) — per-user bucket
  `"User: #{id}"`, applies to the whole `/api` pipeline.

### Background jobs & metrics
- **Oban** is used (e.g. `lib/glific/third_party/kaapi/assistant_clone_worker.ex`,
  `use Oban.Worker`). Not strictly required for v1 (the Kaapi callback drives completion),
  but available if we want retry/timeout handling.
- **Metrics:** `lib/glific/metrics.ex` → `Metrics.increment("Event", org_id)` (per-org).
  Used as `Metrics.increment("Assistant Created", org_id)`. We can add a server-side
  `"Prompt Generated"` counter to complement the PostHog frontend funnel.

### Testing
- ExUnit + Wormwood GraphQL helpers. HTTP mocked with `Tesla.Mock.mock(fn %Tesla.Env{...} ->
  … end)`. GraphQL via `auth_query_gql_by(:op, user, variables: …)`. Examples:
  `test/glific/third_party/kaapi/kaapi_test.exs`,
  `test/glific_web/resolvers/assistants_test.exs` (KB callback flow ~1970–2034).

## 4. Key design implications

1. The prompt-engineering "meta-prompt" (instructions that turn 9 answers into a chatbot
   system prompt) lives **server-side** in a new `Glific.PromptGenerator` context — not in
   the client — so it can be tuned without a frontend release and isn't exposed to users.
2. Because Kaapi `/llm/call` is async, v1 needs: a small persistence table keyed by
   `kaapi_job_id`, a callback route, and a pollable GraphQL query — mirroring the verified
   KB-creation flow. Within the 2–3s UX the spec describes, ~1s polling is comfortable.
3. The Assistant create/update path is **untouched**; the generated text is applied to the
   existing Instructions field on the client before the user saves the assistant normally.
