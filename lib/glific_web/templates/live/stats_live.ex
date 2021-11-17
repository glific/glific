defmodule GlificWeb.StatsLive do
  # If you generated an app with mix phx.new --live,
  # the line below would be: use MyAppWeb, :live_view
  use GlificWeb, :live_view

  def render(assigns) do
    ~H"""
    <h1> Current temperature: <%= @temperature %> </h1>
    """
  end

  def mount(_params, _session, socket) do
    # temperature = Thermostat.get_user_reading(user_id)
    {:ok, assign(socket, :temperature, 10)}
  end
end
