defmodule GlificWeb.UserSocketTest do
  alias GlificWeb.UserSocket
  use GlificWeb.ChannelCase

  @tag :sock
  test "create socket" do
    UserSocket.handle_init(%{}, %Phoenix.Socket{}) |> IO.inspect
  end
end
