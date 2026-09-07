defmodule GlificWeb.Plugs.WebChannelCors do
  @moduledoc """
  Narrows CORS to a known set of origins for the web channel routes, leaving every other route on
  the permissive default the rest of Glific's API has always used.

  This has to run in the endpoint rather than a router pipeline. `CORSPlug` answers a preflight
  `OPTIONS` itself and halts, so the endpoint's own `CORSPlug` would have already replied
  `access-control-allow-origin: *` before the router ever ran — a router-level restriction would
  narrow the real request and leave the preflight wide open, which is no restriction at all.

  Origins come from `:web_channel_allowed_origins`, so staging and an NGO on its own domain do not
  need a code change. A request from an origin not on the list gets no CORS headers back, and the
  browser refuses it.
  """

  @behaviour Plug

  alias Plug.Conn

  @impl Plug
  @spec init(Plug.opts()) :: {Plug.opts(), Plug.opts()}
  def init(_opts),
    do: {CORSPlug.init(origin: allowed_origins()), CORSPlug.init([])}

  @impl Plug
  @spec call(Conn.t(), {Plug.opts(), Plug.opts()}) :: Conn.t()
  def call(%Conn{path_info: ["api", "v1", "web_channel" | _]} = conn, {web_channel, _default}),
    do: CORSPlug.call(conn, web_channel)

  def call(conn, {_web_channel, default}), do: CORSPlug.call(conn, default)

  @spec allowed_origins() :: [Regex.t() | String.t()]
  defp allowed_origins do
    Application.get_env(:glific, :web_channel_allowed_origins, [])
    |> Enum.map(&compile/1)
  end

  # A `*` in a configured origin means one hostname label, not "anything" — `web.*.glific.com`
  # must not match `web.evil.com.glific.com.attacker.net`, so the wildcard is anchored and cannot
  # span a dot.
  @spec compile(String.t()) :: Regex.t()
  defp compile(origin) do
    pattern =
      origin
      |> String.split("*")
      |> Enum.map_join("[a-z0-9-]+", &Regex.escape/1)

    Regex.compile!("\\A#{pattern}\\z", "i")
  end
end
