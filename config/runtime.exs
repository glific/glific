# In this file, we load all configuration and secrets from environment variables.
# Added few checks for debug.
# This file is now used for all releases

import Config
import Dotenvy

source(["config/.env", "config/.env.#{config_env()}", System.get_env()])

http_port = env!("HTTP_PORT", :integer, 4000)

# Helper function to create SSL opts
db_ssl_opts = fn db_type ->
  if Application.get_env(:glific, :environment) != :test && env!("ENABLE_DB_SSL", :boolean, true) do
    pem = "#{db_type}_CACERT_ENCODED" |> env!(:string) |> Base.decode64!()
    File.mkdir_p(Path.join(:code.priv_dir(:glific), "cert"))

    cert_path =
      Path.join(:code.priv_dir(:glific), "cert/#{String.downcase(db_type)}-db-server-ca.pem")

    File.write!(cert_path, pem)

    [
      cacertfile: cert_path,
      verify: :verify_peer,
      server_name_indication:
        env!("#{db_type}_DB_SERVER_NAME_INDICATION", :string!, "localhost")
        |> String.to_charlist()
    ]
  else
    false
  end
end

primary_url = env!("DATABASE_URL", :string!)
primary_ssl_opts = db_ssl_opts.("PRIMARY")

config :glific, Glific.Repo,
  url: primary_url,
  pool_size: env!("POOL_SIZE", :integer, 20),
  show_sensitive_data_on_connection_error: true,
  ssl: primary_ssl_opts,
  prepare: :named,
  parameters: [plan_cache_mode: "force_custom_plan"]

replica_url = env!("READ_REPLICA_DATABASE_URL", :string!, primary_url)

replica_ssl_opts =
  if primary_url != replica_url, do: db_ssl_opts.("REPLICA"), else: primary_ssl_opts

config :glific, Glific.RepoReplica,
  url: replica_url,
  pool_size: env!("POOL_SIZE", :integer, 20),
  show_sensitive_data_on_connection_error: true,
  ssl: replica_ssl_opts,
  prepare: :named,
  parameters: [plan_cache_mode: "force_custom_plan"]

config :glific, :hackney_pool, max_connections: env!("HACKNEY_POOL_SIZE", :integer, 50)

check_origin = [env!("REQUEST_ORIGIN", :string!), env!("REQUEST_ORIGIN_WILDCARD", :string!)]

# Glific endpoint configs
config :glific, GlificWeb.Endpoint,
  server: true,
  http: [:inet6, port: http_port],
  check_origin: check_origin,
  secret_key_base: env!("SECRET_KEY_BASE", :string!),
  url: [host: env!("BASE_URL", :string!)],
  render_errors: [view: GlificWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Glific.PubSub,
  live_view: [signing_salt: env!("SIGNING_SALT", :string!)]

config :glific,
  auth_username: env!("AUTH_USERNAME", :string!),
  auth_password: env!("AUTH_PASSWORD", :string!)

config :glific, :max_rate_limit_request, env!("MAX_RATE_LIMIT_REQUEST", :integer, 180)

config :glific, :bigquery_dedup_timeout_ms, env!("BIGQUERY_DEDUP_TIMEOUT_MS", :integer, 120_000)

config :glific,
       :bigquery_dedup_recv_timeout_ms,
       env!("BIGQUERY_DEDUP_RECV_TIMEOUT_MS", :integer, 150_000)

# AppSignal configs
config :appsignal, :config,
  otp_app: :glific,
  name: "Glific",
  hostname: env!("APPSIGNAL_HOSTNAME", :string),
  active: env!("APPSIGNAL_ACTIVE", :boolean, false),
  revision: Application.spec(:glific, :vsn) |> to_string(),
  push_api_key: env!("APPSIGNAL_PUSH_API_KEY", :string!),
  ecto_repos: [],
  ignore_namespaces: ["gupshup_webhooks", "gupshup_enterprise_webhooks", "flow_editor_controller"],
  instrument_oban: false,
  log_level: env!("APPSIGNAL_LOG_LEVEL", :string!, "info")

config :glific, Glific.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V3", key: Base.decode64!(env!("CIPHER_KEY", :string))},
    old_key:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V2", key: Base.decode64!(env!("OLD_CIPHER_KEY", :string))}
  ]

config :stripity_stripe,
  api_key: env!("STRIPE_API_KEY", :string!),
  signing_secret: env!("STRIPE_SIGNING_SECRET", :string!)

config :glific, Glific.Communications.Mailer,
  region: env!("SES_REGION", :string!, "This is not a region"),
  access_key: env!("SES_KEY", :string!, "This is not a key"),
  secret: env!("SES_SECRET", :string!, "This is not a secret")

config :glific,
  google_captcha_secret_key: env!("RECAPTCHA_SECRET_KEY", :string!, "This is not a secret")

config :glific,
  gcs_file_count: env!("GCS_FILE_COUNT", :integer, 5),
  broadcast_contact_count: env!("BROADCAST_CONTACT_COUNT", :integer, 100),
  broadcast_contact_count_high_tps: env!("BROADCAST_CONTACT_COUNT_HIGH_TPS", :integer, 300)

config :glific,
  open_ai: env!("OPEN_AI_KEY", :string!, "This is not a secret")

config :glific, Glific.OpenAI.ChatGPT, gpt_model: env!("OPEN_AI_MODEL", :string, "gpt-5.1")

config :glific,
  gemini_api_key: env!("GEMINI_API_KEY", :string!, "This is not a secret")

config :glific,
  google_translate: env!("GOOGLE_TRANSLATE_KEY", :string!, "This is not a secret")

config :glific,
  gigalixir_username: env!("GIGALIXIR_USERNAME", :string!, "This is not a secret")

config :glific,
  gigalixir_api_key: env!("GIGALIXIR_API_KEY", :string!, "This is not a secret")

config :glific,
  gigalixir_app_name: env!("GIGALIXIR_APP_NAME", :string!, "This is not a secret")

config :glific,
  google_maps_api_key: env!("GOOGLE_MAPS_API_KEY", :string!, "This is not a secret")

config :glific,
  sheets_chunk_size: env!("SHEETS_CHUNK_SIZE", :integer, 1000)

config :glific,
  ERP_API_KEY: env!("ERP_API_KEY", :string!, "This is not the ERP API key"),
  ERP_SECRET: env!("ERP_SECRET", :string!, "This is not the ERP secret"),
  ERP_ENDPOINT: env!("ERP_ENDPOINT", :string, "This is not a secret")

config :glific,
  open_ai_project: env!("OPEN_AI_PROJECT", :string!, "This is not a secret")

config :glific,
  dify_api_key: env!("DIFY_API_KEY", :string!, "This is not a secret")

config :glific,
  avni_password: env!("AVNI_PASSWORD", :string!, "This is not a secret")

config :glific,
  gupshup_partner_client_secret: env!("GUPSHUP_PARTNER_CLIENT_SECRET", :string!, "")

config :glific, Glific.Erase,
  msg_delete_batch_size: env!("MSG_DELETE_BATCH_SIZE", :integer, 100_000),
  max_msg_rows_to_delete: env!("MAX_MSG_ROWS_TO_DELETE", :integer, 2_000_000)

# Percent of total job metrics to be sent to appsignal
config :glific,
  appsignal_sampling_rate: env!("APPSIGNAL_SAMPLING_RATE", :integer, 100)

upload_adapter =
  if config_env() == :test,
    do: nil,
    else:
      {Tesla.Adapter.Hackney,
       [recv_timeout: 60_000, connect_timeout: 15_000, pool: :kaapi_upload_pool]}

config :glific, Glific.ThirdParty.Kaapi.ApiClient,
  kaapi_endpoint: env!("KAAPI_ENDPOINT", :string, "This is not a secret"),
  kaapi_api_key: env!("KAAPI_API_KEY", :string, "This is not a secret"),
  upload_adapter: upload_adapter

config :glific, Glific.ThirdParty.Kaapi,
  stt_model: env!("KAAPI_STT_MODEL", :string, "gemini-3.1-pro-preview"),
  tts_model: env!("KAAPI_TTS_MODEL", :string, "gemini-3.1-flash-tts-preview")

config :glific, Glific.ThirdParty.Gemini.ApiClient,
  gemini_api_key: env!("GEMINI_API_KEY", :string, "This is not a secret"),
  stt_model: env!("GEMINI_STT_MODEL", :string, "gemini-2.5-pro"),
  tts_model: env!("GEMINI_TTS_MODEL", :string, "gemini-2.5-pro-preview-tts")

config :glific,
  base_domain: env!("GLIFIC_BASE_DOMAIN", :string, "glific.com"),
  api_host_override: env!("GLIFIC_API_HOST_OVERRIDE", :string, nil),
  discord_webhook_url: env!("DISCORD_WEBHOOK_URL", :string, nil)

# The BSP webhooks are unauthenticated, so callers are filtered on the source IPs the
# provider publishes; anything else gets a 403.

# :inet rather than the CIDR library the plug matches with, because config runs before any
# dependency is started.
# The CIDR library the plug matches with rejects a block whose host bits are set, so
# accepting one here would leave a list that looks configured but never matches, and the
# whole range would be answered with 403.
network_address? = fn parsed, prefix_length ->
  {bits, group} = if tuple_size(parsed) == 4, do: {32, 256}, else: {128, 65_536}
  address = parsed |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> acc * group + part end)

  rem(address, Integer.pow(2, bits - prefix_length)) == 0
end

valid_webhook_ip? = fn entry ->
  [address | prefix] = String.split(entry, "/", parts: 2)

  case :inet.parse_address(String.to_charlist(address)) do
    {:error, _reason} ->
      false

    {:ok, parsed} ->
      max_length = if tuple_size(parsed) == 4, do: 32, else: 128

      case prefix do
        [] ->
          true

        [length] ->
          case Integer.parse(length) do
            {prefix_length, ""} when prefix_length >= 0 and prefix_length <= max_length ->
              network_address?.(parsed, prefix_length)

            _invalid ->
              false
          end
      end
  end
end

webhook_ips = fn variable ->
  case env!(variable, :string, nil) do
    unset when unset in [nil, ""] ->
      []

    ips ->
      ips
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(fn entry ->
        if valid_webhook_ip?.(entry),
          do: entry,
          else:
            raise("""
            #{variable} contains "#{entry}", which is not an IP address or CIDR block.

            A CIDR block must be given as its network address, so 192.0.2.0/24 rather than
            192.0.2.10/24.

            Expected a comma separated list, for example:

                gigalixir config:set #{variable}="a.b.c.d,e.f.g.h,w.x.y.z/24"
            """)
      end)
  end
end

# Only :prod is configured. An unset list means the provider is not filtered, which keeps
# dev and test working against localhost.
if config_env() == :prod do
  gupshup_webhook_ips = webhook_ips.("GUPSHUP_WEBHOOK_IPS")

  # Booting without this list would leave the busiest webhook accepting forged messages
  # from any caller, so refuse to start rather than come up unprotected.
  if gupshup_webhook_ips == [],
    do:
      raise("""
      GUPSHUP_WEBHOOK_IPS is not set.

      The /gupshup webhook is unauthenticated and is guarded only by Gupshup's published
      callback IPs, so Glific will not boot without them.

      Set it to Gupshup's comma separated callback IPs, CIDR blocks allowed:

          gigalixir config:set GUPSHUP_WEBHOOK_IPS="a.b.c.d,e.f.g.h,w.x.y.z/24"
      """)

  config :glific, :gupshup_webhook_ips, gupshup_webhook_ips
  config :glific, :gupshup_enterprise_webhook_ips, webhook_ips.("GUPSHUP_ENTERPRISE_WEBHOOK_IPS")
  config :glific, :maytapi_webhook_ips, webhook_ips.("MAYTAPI_WEBHOOK_IPS")
end

search_repo_module =
  if(env!("USE_REPLICA_DB", :boolean, false), do: Glific.RepoReplica, else: Glific.Repo)

config :glific, Glific.Searches, repo_module: search_repo_module

unless config_env() == :test do
  config :glific, Glific.ThirdParty.Superset.ApiClient,
    base_url: env!("SUPERSET_URL", :string, "https://not-configured.invalid/api/v1"),
    dashboard_id: env!("SUPERSET_DASHBOARD_ID", :string, "this_is_not_a_dashboard_id"),
    guest_username: env!("SUPERSET_GUEST_USERNAME", :string, "this_is_not_a_username"),
    username: env!("SUPERSET_USERNAME", :string, "this_is_not_a_username"),
    password: env!("SUPERSET_PASSWORD", :string, "this_is_not_a_password")
end

# Provider credentials for Glific AI. Secrets: environment only, never committed.
# req_llm resolves these itself; nil simply means no provider is configured, which
# Glific.AI reports as a failure rather than crashing at boot.
config :req_llm,
  anthropic_api_key: env!("ANTHROPIC_API_KEY", :string, nil),
  openai_api_key: env!("OPENAI_API_KEY", :string, nil)
