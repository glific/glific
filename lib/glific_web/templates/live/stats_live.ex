defmodule GlificWeb.StatsLive do
  @moduledoc """
  StatsLive uses phoenix live view to show current stats
  """
  use GlificWeb, :live_view

  @doc """
  Receives the socket.assigns and is responsible for returning rendered content
  """
  @spec render(Plug.Conn.t()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <h1> Current temperature: <%= @temperature %> </h1>
    """
  end

  @doc """
  Wires up socket assigns necessary for rendering the view
  """
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    # temperature = Thermostat.get_user_reading(user_id)
    {:ok, assign(socket, :temperature, 10)}
  end
end
