%Doctor.Config{
  ignore_modules: [],
  ignore_paths: [
    ~r(lib/glific_web/views/.*),
    "lib/glific/application.ex",
    "lib/glific_web.ex",
    "lib/glific_web/telemetry.ex",
    "lib/glific/enums/ecto_enums.ex"
  ],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_spec_coverage: 0,
  moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  umbrella: false
}
