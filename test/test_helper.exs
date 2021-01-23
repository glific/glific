Code.put_compiler_option(:warnings_as_errors, true)

ExUnit.start(exclude: :pending)
Faker.start()
Ecto.Adapters.SQL.Sandbox.mode(Glific.Repo, :manual)
