defmodule GlificWeb.StatsLive do
  @moduledoc """
  StatsLive uses phoenix live view to show current stats
  """
  use GlificWeb, :live_view

  alias Glific.Reports

  def mount(_params, _session, socket) do
    if(connected?(socket)) do
      :timer.send_interval(1000, self(), :refresh)
    end

    socket = assign_stats(socket, :init)
    {:ok, socket}
  end

  def handle_info(:refresh, socket) do
    {:noreply, assign_stats(socket, :call)}
  end

  def handle_info({:get_stats, kpi}, socket) do
    {:noreply, assign(socket, kpi, Reports.get_kpi(kpi))}
  end

  defp assign_stats(socket, :init) do
    stats = Enum.map(Reports.kpi_list(), &{&1, "loading.."})
    assign(socket, Keyword.merge(stats, page_title: "Glific Dashboard"))
  end

  defp assign_stats(socket, :call) do
    Enum.map(Reports.kpi_list(), &send(self(), {:get_stats, &1}))
    socket
  end
end
