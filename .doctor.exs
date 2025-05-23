%Doctor.Config{
  ignore_modules: [
    Glific.Media,
    Glific.Media.Type,
    Glific.Sandbox,
    GlificWeb.Plugs.AppsignalAbsinthePlug,
    # i have no idea where this is coming from, most likely a bug in doctor
    Inspect.Glific.Users.User,
    Glific.Users,
    Glific.Clients
  ],
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
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  reporter: Doctor.Reporters.Full,
  raise: false,
  umbrella: false
}
