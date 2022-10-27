defmodule GlificWeb.GlificDashboardLive do
  use GlificWeb, :live_view

  def mount(_params, _session, socket) do
    if(connected?(socket)) do
      :timer.send_interval(1000, self(), :refresh)
    end

    socket = assign_stats(socket, :init)
    {:ok, socket}
  end

  def handle_info(:refresh, socket) do
    socket = assign_stats(socket, :call)
    # socket = assign(socket, :contact_count, 2000)
    {:noreply, socket}
  end

  def handle_info({:get_stats, kpi}, socket) do
    count = Enum.random(1..1000)
    socket = assign(socket, kpi, count)
    {:noreply, socket}
  end

  defp assign_stats(socket, :init) do
    assign(socket,
      page_title: "Glific Dashboard",
      conversation_count: 10,
      active_flow_count: 20,
      contact_count: 0,
      opted_in_contacts_count: 0,
      opted_out_contacts_count: 0
    )
  end

  defp assign_stats(socket, :call) do
    stats = [
      :conversation_count,
      :active_flow_count,
      :contact_count,
      :opted_in_contacts_count,
      :opted_out_contacts_count
    ]

    Enum.map(stats, &send(self(), {:get_stats, &1}))

    socket
  end
end
