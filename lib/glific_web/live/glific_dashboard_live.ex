defmodule GlificWeb.GlificDashboardLive do
  use GlificWeb, :live_view

  def mount(_params, _session, socket) do
    socket = assign(socket, :contact_count, 0)
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1> Glific Dashboard</h1>

    <div>
      <div class="card">
        <div class="card-body">
          <h3>Contacts</h3>
          <h3>454</h3>
        </div>
      </div>
    </div>
    """
  end
end
