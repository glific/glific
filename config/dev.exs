import Config

# setting the state of the environment for use within code base
config :glific, :environment, :dev

db_host = "127.0.0.1" |> to_charlist()
cert_dir = "/Users/lobo/.postgresql"

decode_cert = fn cert ->
  [{:Certificate, der, _}] = :public_key.pem_decode(cert |> File.read!())
  der
end

decode_key = fn cert ->
  [{:ECPrivateKey, key, :not_encrypted}] = :public_key.pem_decode(cert |> File.read!())
  {:ECPrivateKey, key}
end

ca_cert = "#{cert_dir}/rootCA.pem"
client_key = "#{cert_dir}/postgresql.key"
client_cert = "#{cert_dir}/postgresql.crt"

ssl_opts =
  if ca_cert,
    do: [
      cacerts: [decode_cert.(ca_cert)],
      verify: :verify_none,
      versions: [:"tlsv1.3"],
      key: decode_key.(client_key),
      cert: decode_cert.(client_cert),
      server_name_indication: db_host,
      customize_hostname_check: [
        match_fun: fn a, b ->
          IO.inspect(a, label: "MATCH: #{b}")
          true
        end
      ]
      # verify_fun: {&:ssl_verify_hostname.verify_fun/3, []}
    ]

# lets experiment with DB SSL here
config :glific, Glific.Repo,
  ssl: true,
  ssl_opts: ssl_opts

config :glific, GlificWeb.Endpoint, http: [ip: {0, 0, 0, 0}, port: 4000]

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :glific, GlificWeb.Endpoint,
  # EXPERIMENT TO get everyone to switch to https even for local development
  # So we can record audio etc, which requires ssl
  https: [
    port: 4001,
    cipher_suite: :strong,
    certfile: "priv/cert/glific.test+1.pem",
    keyfile: "priv/cert/glific.test+1-key.pem"
  ],
  debug_errors: true,
  code_reloader: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

# config :absinthe, Absinthe.Logger,
#   pipeline: true,
#   level: :debug

# Watch static and templates for browser reloading.
config :glific, GlificWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/glific_web/(live|views)/.*(ex)$",
      ~r"lib/glific_web/templates/.*(eex)$"
    ]
  ]

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :appsignal, :config,
  otp_app: :glific,
  active: false,
  env: :dev

config :glific, Glific.Communications.Mailer, adapter: Swoosh.Adapters.Local

import_config "dev.secret.exs"
