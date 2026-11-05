defmodule GlificWeb.Plugs.HealthCheck do
  @moduledoc """
  The only HTTP surface of a worker node (`NODE_ROLE=worker`).

  Gigalixir adds a replica to its app's cluster DNS name only once port 4000 answers, so a worker
  has to listen even though it serves no traffic. It does so through this plug on a bare
  `Plug.Cowboy` listener, while `GlificWeb.Endpoint` runs with `server: false`: the endpoint stays
  up for PubSub and subscription publishing, and the API and its websockets are not reachable on
  the worker's public domain. A plug inside the endpoint could not do this, because socket
  dispatch happens before the endpoint's plugs run.

  It answers without touching the database, so a database blip does not get worker replicas
  restarted.
  """

  @behaviour Plug

  alias Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Conn{method: method, path_info: path_info} = conn, _opts)
      when method in ["GET", "HEAD"] and path_info in [[], ["health"]],
      do: Conn.send_resp(conn, 200, "ok")

  def call(conn, _opts), do: Conn.send_resp(conn, 404, "")
end
