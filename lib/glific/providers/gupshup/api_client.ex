defmodule Glific.Providers.Gupshup.ApiClient do
  use Tesla
  plug Tesla.Middleware.BaseUrl, Application.fetch_env!(:glific, :provider_url)
  plug Tesla.Middleware.Logger, log_level: :debug

  plug Tesla.Middleware.Headers, [
    {"apikey", Application.fetch_env!(:glific, :provider_key)}
  ]

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Plug.Conn.Query.encode/1
end
