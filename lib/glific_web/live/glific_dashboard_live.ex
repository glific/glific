defmodule GlificWeb.GlificDashboardLive do
  use GlificWeb, :live_view

  def mount(_params, _session, socket) do
    socket = assign(socket, contact_count: 0, page_title: "Glific Dashboard")
    {:ok, socket}
  end
end
