[
  ## all available options with default values (see `mix check` docs for description)
  # parallel: true,
  # skipped: true,

  ## list of tools (see `mix check` docs for defaults)
  tools: [
    ## curated tools may be disabled (e.g. the check for compilation warnings)
    # {:compiler, false}
    {:sobelow, false},
    {:mix_audit, false},
    {:npm_test, false},
    {:formatter, false},

    ## ...or adjusted (e.g. use one-line formatter for more compact credo output)
    {:credo, "mix credo --format oneline --strict"},
    # {:ex_unit, "mix test_full", detect: [{:file, "test"}]},

    ## ...or reordered (e.g. to see output from ex_unit before others)
    ## {:ex_unit, order: -1},

    ## custom new tools may be added (mix tasks or arbitrary commands)
    # {:my_mix_task, command: "mix release", env: %{"MIX_ENV" => "prod"}},
    # {:my_arbitrary_tool, command: "npm test", cd: "assets"},
    # {:my_arbitrary_script, command: ["my_script", "argument with spaces"], cd: "scripts"}

    {:mix_format, "mix format"},
    {:dialyzer, "mix dialyzer --quiet", detect: [{:package, :dialyxir}]}
    # We will enable it later
    # {:sobelow, "mix sobelow --skip --exit", umbrella: [recursive: true], detect: [{:package, :sobelow}]},
    # {:mix_coveralls, "mix coveralls", [{:deps, [:ex_unit]}, {:env, %{"MIX_ENV" => "test"}}]}
  ]
]
