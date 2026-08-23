# :eval_live tests make real, paid provider calls. They are the live-shape guard against
# req_llm's structs drifting, so they are run deliberately — `mix test --only eval_live` —
# before a dependency bump or a model change ships, never as part of the default suite.
#
# :eval tests are the stubbed/deterministic AI skill eval harness (test/glific/ai/evals/).
# They are cheap and safe to run in CI, but are excluded from the default `mix test` run so
# that day-to-day local runs stay focused on unit/integration coverage — run them deliberately
# with `mix test --only eval`, which is exactly what the dedicated CI job does.
ExUnit.start(exclude: [:pending, :eval_live, :eval])
Faker.start()
Ecto.Adapters.SQL.Sandbox.mode(Glific.Repo, :manual)
