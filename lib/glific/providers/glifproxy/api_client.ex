defmodule Glific.Providers.Glifproxy.ApiClient do
  @moduledoc """
  Http API client to intract with Glifproxy
  """
  alias Plug.Conn.Query
  use Tesla
  plug Tesla.Middleware.BaseUrl, Application.fetch_env!(:glific, :provider_url)
  plug Tesla.Middleware.Logger, log_level: :debug

  plug Tesla.Middleware.Headers, [
    {"apikey", Application.fetch_env!(:glific, :provider_key)}
  ]

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
end
