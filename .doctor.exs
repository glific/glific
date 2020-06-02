%Doctor.Config{
  ignore_modules: [],
  ignore_paths: [~r(lib/glific_web/views/.*), "lib/glific/application.ex", "lib/glific/ecto_enums.ex", "lib/glific_web.ex"],
  min_module_doc_coverage: 30,
  min_module_spec_coverage: 30,
  min_overall_doc_coverage: 30,
  min_overall_spec_coverage: 30,
  moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  umbrella: false
}
