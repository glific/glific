defmodule GlificWeb.RateLimitPlug do
  @moduledoc """
  Enforcing rate limits on our AP's both authenticated and non-authenticated

  Mounted twice, because the two jobs need different places in the stack:

      plug(GlificWeb.RateLimitPlug, :global)   # GlificWeb.Endpoint
      plug(GlificWeb.RateLimitPlug)            # the :api pipeline

  The `:api` pipeline only runs once the router has matched a route, so a request for a path that
  matches nothing never reached this plug at all and was unlimited. The `:global` mode closes
  that, and has to live in the endpoint to do so.

  It cannot simply be the same mode mounted earlier. `:current_user` is assigned by
  `GlificWeb.APIAuthPlug` inside the `:api` pipeline, so at endpoint level every request — a
  signed-in user's GraphQL call included — would look unauthenticated and share the stricter
  bucket. The default mode also reads `conn.params`, which is unfetched before `Plug.Parsers`. And
  it would newly throttle the BSP webhooks, which are high volume from a handful of addresses.

  So `:global` asks the router whether the path matches anything and only counts the requests that
  match nothing. Its bucket is the source address alone rather than address and path, so sweeping
  many URLs buys a caller nothing. Over the limit answers 429.

  Each limit's count is an environment variable read at boot — `RATE_LIMIT_API_GLOBAL`,
  `RATE_LIMIT_API_UNAUTHENTICATED`, `RATE_LIMIT_API_AUTHENTICATED`, `RATE_LIMIT_API_PHONE` and
  `RATE_LIMIT_WEB_CHANNEL_API` — while its window is fixed in `config/config.exs`.
  """

  alias GlificWeb.{Router, Tenants}
  alias Plug.Conn

  @behaviour Plug

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, :global) do
    if matched_route?(conn),
      do: conn,
      else: rate_limit(conn, :rate_limit_api_global, "Global: #{Tenants.remote_ip(conn)}")
  end

  # The web channel is embedded on public sites, where a school or office puts many unrelated
  # beneficiaries behind one address, so it gets its own and far more generous budget rather than
  # sharing the staff one.
  def call(conn, :web_channel) do
    rate_limit(conn, :rate_limit_web_channel_api, "WebChannel: #{Tenants.remote_ip(conn)}")
  end

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      nil -> rate_limit_unauthenticated(conn)
      user -> rate_limit(conn, :rate_limit_api_authenticated, "User: #{user.id}")
    end
  end

  defp rate_limit(conn, limit_name, bucket_name) do
    case Glific.RateLimit.check(limit_name, bucket_name) do
      # Do nothing, pass on to the next plug
      :ok -> conn
      {:error, :rate_limited} -> render_error(conn)
    end
  end

  defp matched_route?(conn) do
    Router
    |> Phoenix.Router.route_info(effective_method(conn), decoded_path(conn), conn.host)
    |> Kernel.!=(:error)
  end

  # Plug.Head rewrites HEAD to GET further down the endpoint, so the router only declares GET.
  defp effective_method(%Conn{method: "HEAD"}), do: "GET"

  # A preflight asks permission for another method, so judge the route by that one. Judging it by
  # OPTIONS would count every preflight to a route the router declares by name as unrouted.
  defp effective_method(%Conn{method: "OPTIONS"} = conn) do
    case Conn.get_req_header(conn, "access-control-request-method") do
      [requested | _] -> String.upcase(requested)
      [] -> "OPTIONS"
    end
  end

  defp effective_method(%Conn{method: method}), do: method

  # route_info/4 does not decode a path it is given as a string, but the router itself does.
  defp decoded_path(conn), do: Enum.map(conn.path_info, &URI.decode/1)

  # Keyed on the address alone. Keying it on address and path let a caller multiply its allowance
  # by varying the path, and on routes with a glob segment the path is caller-controlled, so the
  # number of live ExRated buckets was unbounded from unauthenticated traffic.
  defp rate_limit_unauthenticated(conn) do
    conn
    |> rate_limit(:rate_limit_api_unauthenticated, "Unauthenticated: #{Tenants.remote_ip(conn)}")
    |> rate_limit_phone()
  end

  defp rate_limit_phone(%Conn{halted: true} = conn), do: conn

  # Charged in addition to the address bucket, not instead of it: on its own it let one address
  # rotate phone numbers for an unlimited number of attempts.
  defp rate_limit_phone(conn) do
    case get_in(conn.params, ["user", "phone"]) do
      phone when is_binary(phone) ->
        rate_limit(conn, :rate_limit_api_phone, "Authorization: " <> phone)

      _no_phone ->
        conn
    end
  end

  defp render_error(conn) do
    conn
    |> Conn.send_resp(429, "Rate limit exceeded")
    # Stop execution of further plugs, return response now
    |> Conn.halt()
  end
end
