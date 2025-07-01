defmodule GlificWeb.UserSocketTest do
  alias GlificWeb.UserSocket
  use GlificWeb.ChannelCase, async: true

  @tag :sock
  test "create socket" do
    Absinthe.GraphqlWS.Socket.__connect__(
      UserSocket,
      socket(UserSocket, %{}, %{some: :assign}),
      schema: GlificWeb.Schema
    )

    # {:ok, socket} = connect(UserSocket, %{"some" => "params"}, subprotocols: ["graphql-transport-ws"]) |> IO.inspect()
  end
end
