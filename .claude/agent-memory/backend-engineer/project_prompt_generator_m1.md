---
name: project-prompt-generator-m1
description: M1 backend for prompt-generation engine — schema, context, Kaapi fn, tests; M2 (GraphQL + controller route) is a separate PR
metadata:
  type: project
---

M1 is merged into `feature/prompt-generator-m1-engine`. No GraphQL, no web layer, no Oban worker — pure internal API.

**Files created:**
- `priv/repo/migrations/20260617054815_create_prompt_generation_requests.exs`
- `lib/glific/prompt_generator/prompt_generation_request.ex` — Ecto schema with `Ecto.Enum` (plain string column + enum in schema, NOT a Postgres defenum)
- `lib/glific/prompt_generator.ex` — context: `generate_prompt/3`, `handle_callback/1`, `build_llm_payload/3`, `format_answers/1`
- `test/glific/prompt_generator_test.exs` — 24 tests, all green

**Files modified:**
- `lib/glific/third_party/kaapi.ex` — added `generate_prompt/2` between `text_to_speech` and `normalize_kaapi_body`

**Key decisions:**
- Kaapi `call_llm/2` returns atom-keyed body via `keys: :atoms` Tesla middleware; extract `body.data.job_id`
- Callback URL pattern: `Glific.api_callback_base(org.shortcode) <> "/kaapi/prompt_generation"` — route wired in M2
- `handle_callback/1` uses `Repo.fetch_by(PromptGenerationRequest, %{kaapi_job_id: job_id})` WITHOUT `skip_organization_id` — org context is set by `SubdomainPlug` in the endpoint for all requests (including unauthenticated Kaapi callbacks)
- `Ecto.Enum` with `values: [:in_progress, :ready, :failed]` on a plain `:string` DB column (NOT a Postgres enum type)

**Why:** M2 will add the GraphQL types/resolver, the `/kaapi/prompt_generation` controller action, and the Bruno doc entry. M1 is the pure engine layer.
