defmodule GlificWeb.Plugs.WebChannelCors do
  @moduledoc """
  Narrows CORS to `:web_channel_allowed_origins` for the web channel routes, leaving the rest of
  the API on its permissive default.

  Runs in the endpoint, not a router pipeline: `CORSPlug` answers a preflight itself and halts, so
  anything later would narrow the real request and leave the preflight wide open.
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

  # Anchored, and `*` cannot span a dot, or a domain an attacker registers would match.
  @spec compile(String.t()) :: Regex.t()
  defp compile(origin) do
    pattern =
      origin
      |> String.split("*")
      |> Enum.map_join("[a-z0-9-]+", &Regex.escape/1)

    Regex.compile!("\\A#{pattern}\\z", "i")
  end
end
