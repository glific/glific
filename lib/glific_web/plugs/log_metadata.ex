defmodule GlificWeb.Plugs.LogMetadata do
  @moduledoc """
  Attaches request context to `Logger` metadata so every line logged while serving the request
  carries it. Rendering is left to the `:default_formatter` metadata whitelist in `config/config.exs`.
  """

  alias Plug.Conn

  @behaviour Plug

  # Real browsers stay well under this; the cap bounds caller-controlled bytes on every log line.
  @max_user_agent 256

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Conn.t(), Plug.opts()) :: Conn.t()
  def call(conn, _opts) do
    case Conn.get_req_header(conn, "user-agent") do
      [user_agent | _] ->
        Logger.metadata(user_agent: String.slice(user_agent, 0, @max_user_agent))

      [] ->
        :ok
    end

    conn
  end
end
