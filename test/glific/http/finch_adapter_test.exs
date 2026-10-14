defmodule Glific.Http.FinchAdapterTest do
  use ExUnit.Case, async: true

  alias Glific.Http.FinchAdapter

  setup do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    on_exit(fn -> :gen_tcp.close(listen) end)
    %{listen: listen, url: "http://127.0.0.1:#{port}/"}
  end

  defp request(url, opts) do
    FinchAdapter.call(%Tesla.Env{method: :get, url: url}, [name: Glific.Finch] ++ opts)
  end

  defp serve(listen, response) do
    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(socket, 0)
      :gen_tcp.send(socket, response)
      Process.sleep(:infinity)
    end)
  end

  defp accept_and_hang(listen) do
    spawn_link(fn ->
      {:ok, _socket} = :gen_tcp.accept(listen)
      Process.sleep(:infinity)
    end)
  end

  test "returns the response for a successful request", %{listen: listen, url: url} do
    serve(listen, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok")

    assert {:ok, %Tesla.Env{status: 200, body: "ok"}} = request(url, receive_timeout: 1_000)
  end

  test "returns a redirect as a plain 3xx response", %{listen: listen, url: url} do
    serve(listen, "HTTP/1.1 302 Found\r\nlocation: /next\r\ncontent-length: 0\r\n\r\n")

    assert {:ok, %Tesla.Env{status: 302}} = request(url, receive_timeout: 1_000)
  end

  test "returns {:error, :timeout} when the server does not respond in time", %{
    listen: listen,
    url: url
  } do
    accept_and_hang(listen)

    assert {:error, :timeout} = request(url, receive_timeout: 100)
  end

  test "returns {:error, :econnrefused} when nothing listens on the port", %{
    listen: listen,
    url: url
  } do
    :gen_tcp.close(listen)

    assert {:error, :econnrefused} = request(url, receive_timeout: 1_000)
  end

  test "returns {:error, :checkout_timeout} when the pool has no free connection", %{
    listen: listen,
    url: url
  } do
    name = :"finch_adapter_test_#{System.unique_integer([:positive])}"
    start_supervised!({Finch, name: name, pools: %{default: [size: 1]}})
    accept_and_hang(listen)

    env = %Tesla.Env{method: :get, url: url}
    Task.start(fn -> FinchAdapter.call(env, name: name, receive_timeout: 5_000) end)
    Process.sleep(100)

    assert {:error, :checkout_timeout} =
             FinchAdapter.call(env, name: name, receive_timeout: 5_000, pool_timeout: 100)
  end
end
