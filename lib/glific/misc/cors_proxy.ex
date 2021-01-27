defmodule Glific.CorsProxy do
  @moduledoc """
  CorsProxy keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Plug.Conn
  import Plug.Conn, only: [send_resp: 3, put_resp_header: 3]
  require Logger

  @request_blacklist ~w[host accept-language]
  @response_whitelist ~w[Content-Encoding Content-Type]

  @doc false
  @spec request(atom, String.t(), list(), any) :: any()
  def request(method, url, headers, body) when is_map(body) do
    {:ok, body} = body |> Jason.encode()
    request(method, url, headers, body)
  end

  @doc false
  @spec request(atom, list(), list(), any) :: any()
  def request(method, [protocol | path_info], headers, body) do
    path =
      path_info
      |> Enum.join("/")

    url = "#{protocol}//#{path}"

    Logger.info("#{method} #{url}")
    Logger.info("Headers: #{inspect(headers)}")
    Logger.info("Body: #{body}")
    HTTPoison.request(method, url, body, filter_request_headers(headers))
  end

  @doc false
  @spec write_response({atom(), any}, Conn.t()) :: Conn.t() | no_return()
  def write_response({:ok, response}, conn) do
    response.headers
    |> filter_response_headers
    |> Enum.reduce(conn, fn {name, value}, acc ->
      put_resp_header(acc, name, value)
    end)
    |> put_access_control_headers
    |> send_resp(response.status_code, response.body)
  end

  def write_response({:error, data}, conn) do
    Logger.error(inspect(data))
    send_resp(conn, 400, "")
  end

  @spec filter_request_headers(list()) :: list()
  defp filter_request_headers(headers) do
    Enum.filter(headers, fn {name, _value} ->
      Enum.all?(@request_blacklist, fn x -> x != name end)
    end)
  end

  defp filter_response_headers(headers) do
    headers
    |> Enum.filter(fn {name, _} ->
      Enum.any?(@response_whitelist, fn x -> x == name end)
    end)
    |> Kernel.++([
      {"Accept-Language", "en-US"}
    ])
  end

  @doc false
  @spec put_access_control_headers(Conn.t()) :: Conn.t()
  def put_access_control_headers(conn) do
    conn
    |> put_resp_header("Access-Control-Allow-Headers", "*")
    |> put_resp_header("Access-Control-Allow-Methods", "*")
    |> put_resp_header("Access-Control-Allow-Origin", "*")
  end
end
