[
  ## all available options with default values (see `mix check` docs for description)
  # parallel: true,
  # skipped: true,

  ## list of tools (see `mix check` docs for defaults)
  tools: [
    ## curated tools may be disabled (e.g. the check for compilation warnings)
    # {:sobelow, false},
    # {:compiler, false}

    ## ...or adjusted (e.g. use one-line formatter for more compact credo output)
    {:credo, "mix credo --format oneline"},

    ## ...or reordered (e.g. to see output from ex_unit before others)
    # {:ex_unit, order: -1},

    ## custom new tools may be added (mix tasks or arbitrary commands)
    # {:my_mix_task, command: "mix release", env: %{"MIX_ENV" => "prod"}},
    # {:my_arbitrary_tool, command: "npm test", cd: "assets"},
    # {:my_arbitrary_script, command: ["my_script", "argument with spaces"], cd: "scripts"}

    {:mix_doctor, command: "mix doctor"},
    {:mix_coveralls, command: "mix coveralls", env: %{"MIX_ENV" => "test"}}
  ]
]
