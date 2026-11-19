defmodule Glific.Docs.StubEmbeddings do
  @moduledoc """
  Answers embedding requests in the test environment, so the suite never
  reaches a provider.

  Every vector points the same way, which exercises the request path without
  saying anything about ranking. A test that cares about ranking supplies its
  own vectors to `Glific.Docs.semantic/3`.
  """

  @behaviour Plug

  @impl Plug
  @spec init(term()) :: term()
  def init(options), do: options

  @doc "Responds to one embedding request with vectors of the width it asked for."
  @impl Plug
  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, _options) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    request = Jason.decode!(body)
    width = Map.get(request, "dimensions", 256)

    data =
      request
      |> Map.fetch!("input")
      |> List.wrap()
      |> Enum.with_index(fn _input, index ->
        %{"embedding" => List.duplicate(0.1, width), "index" => index}
      end)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => data, "model" => "stub"}))
  end
end
