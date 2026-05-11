---
description: Diagnose and fix failing tests in glific
---

Diagnose and fix failing `glific` tests using this workflow:

1. Reproduce failures with `mix test path/to/test_file.exs:line` when a line is known, `mix test path/to/test_file.exs` for a whole file, otherwise `mix test` (or `mix test --failed` after a prior run).
2. Capture the first failing assertion and stack trace, then identify the true root cause (not cascading failures from earlier tests).
3. Locate the context module, resolver, schema, or worker under test and confirm intended behavior against `@moduledoc` / `@doc` and similar callers.
4. Fix in this order:
   - test setup (org context, fixtures, sandbox/async issues)
   - stale expectations vs current API or schema shape
   - flaky ordering or shared global state
   - real product regression
5. Apply the smallest safe fix, preferring test or fixture adjustments when behavior is correct but the test is wrong; change application code only for real regressions or clarified requirements.
6. Follow these conventions while fixing:
   - use `Glific.DataCase` / `GlificWeb.ConnCase` / `GlificWeb.ChannelCase` as appropriate; ensure `Repo.put_organization_id/1` and fixtures match multi-tenant assumptions
   - prefer existing helpers and fixtures in `test/support/` (e.g. `fixtures.ex`) over ad-hoc inserts
   - for GraphQL endpoint tests, use patterns from `ConnCase` (e.g. `auth_query_gql_by/3`) and match Absinthe schema/resolver contracts
   - mock external HTTP with `Tesla.Mock` (or project Mox modules) instead of hitting real services
   - keep async tests (`async: true`) isolated: no shared mutable process state, no reliance on execution order
7. Re-run the targeted test file (or line) and report pass/fail.
8. If shared behavior changed, run `mix test` for the affected directory or full suite as appropriate, and report remaining failures.
9. Summarize:
   - root cause
   - files changed
   - commands run
   - final test status
