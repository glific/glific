[
  parallel: true,
  # skipped: true,
  tools: [
    {:sobelow, false},
    {:mix_audit, false},
    {:npm_test, false},
    {:formatter, false},
    {:credo, "mix credo --format oneline --strict"},
    # Disabling ex_unit as we have a separate GitHub action for it
    {:ex_unit, false},
    {:mix_format, "mix format"},
    {:dialyzer, "mix dialyzer --quiet", detect: [{:package, :dialyxir}]}
  ]
]
