---
name: fix-flaky-tests
description: Diagnose and fix flaky tests in Glific by reproducing intermittency, isolating ordering and global-mock conflicts, applying the smallest safe fix, and verifying stability with repeated targeted and suite runs. Use when the user reports flaky or nondeterministic test failures, or shares CI logs for intermittent failures.
disable-model-invocation: true
effort: xhigh
---

# Fix Flaky Tests

Use this skill to investigate and fix flaky tests with a strict, evidence-first workflow.

## Required Inputs

Do not begin diagnosis until one of these is provided by the user:

1. A list of flaky tests (file path, optionally line number), or
2. CI logs showing intermittent failures.

If neither is provided, ask for it first.

## Workflow

Follow the steps in order and do not skip verification.

1. **Collect failure target**
   - Parse failing test names, files, line numbers, stack traces, and error shape.
   - Identify whether failures are assertion mismatches, timeouts, process exits, or mock errors.

2. **Reproduce locally (targeted)**
   - Run targeted tests multiple times to confirm intermittency.
   - Recommended loop pattern:
     - `mix test path/to/test_file.exs:line`
     - `mix test path/to/test_file.exs`
     - `mix test`
     - repeat each at least 3 times when needed.

3. **Classify likely root cause**
   - **Ordering-dependent assertions**
     - Symptoms: list/record ordering changes between runs, but set of records is same.
     - Check for missing explicit ordering in queries or brittle positional assertions.
     - Fix by enforcing deterministic order or by asserting order-independently where business behavior allows.
   - **Conflicting global mocks**
     - Symptoms: failures appear only when run with other tests; mock expectations leak or conflict.
     - Check for shared/global mocks configured across tests or modules.
     - Fix by removing conflicting global mocks, scoping mocks per test, and isolating setup/teardown.
   - **Other causes**
     - Common categories: shared mutable state, async race conditions, time-dependent logic, organization context leakage, sandbox misuse, random data assumptions, external service stubs not reset.
     - Validate each hypothesis with direct evidence before changing code.

4. **Apply smallest safe fix**
   - Prefer test/fixture/setup fixes when product behavior is already correct.
   - Change application code only when there is proven behavioral regression.
   - Keep fixes minimal and localized.

5. **Hard guardrail**
   - If root cause cannot be demonstrated with evidence, **do not guess**.
   - Respond clearly: unable to determine root cause and unable to safely fix yet.

6. **Verify after fix (mandatory)**
   - Run the flaky test(s) individually **3 times**.
   - Run whole suite (or nearest practical full-scope suite) **3 times**.
   - Only conclude fixed when all required runs pass consistently.

7. **Report**
   - Root cause and why it was flaky.
   - Files changed.
   - Commands run (including repeated runs).
   - Final pass/fail matrix for individual and suite runs.

## Glific Conventions To Respect

- Use correct test case modules (`Glific.DataCase`, `GlificWeb.ConnCase`, `GlificWeb.ChannelCase`).
- Keep multi-tenant assumptions intact (`Repo.put_organization_id/1`, organization-aware fixtures).
- Prefer existing fixtures/helpers under `test/support/fixtures.ex`.
- Use `Tesla.Mock` or project mock infrastructure for external calls.
- Keep async tests isolated and free of shared mutable state.

## Suggested Additional Ways To Tackle Flaky Tests

- Add deterministic ordering (`order_by`) to queries when order matters.
- Replace brittle positional assertions with order-independent assertions when domain allows.
- Scope mocks per test and reset mock state between tests.
- Reduce shared setup in `setup_all`; move mutable setup into `setup`.
- Disable async selectively for tests that cannot be isolated safely.
- Use deterministic time/randomness controls (fixed timestamps, seeded randomness).
- Run random order or repeated stress runs to expose hidden coupling.
- Capture and compare failing vs passing run artifacts (logs, DB records, process state).
