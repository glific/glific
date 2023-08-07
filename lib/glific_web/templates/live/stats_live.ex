defmodule GlificWeb.StatsLive do
  @moduledoc """
  StatsLive uses phoenix live view to show current stats
  """
  use GlificWeb, :live_view

  alias Glific.Reports

  @doc false
  @spec mount(any(), any(), any()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:ok, Phoenix.LiveView.Socket.t(), Keyword.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(3000, self(), :refresh)
    end

    socket = assign_stats(socket, :init)
    {:ok, socket}
  end

  @doc false
  @spec handle_info(any(), any()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:refresh, socket) do
    {:noreply, assign_stats(socket, :call)}
  end

  def handle_info({:get_stats, kpi}, socket) do
    org_id = get_org_id(socket)
    {:noreply, assign(socket, kpi, Reports.get_kpi(kpi, org_id))}
  end

  @spec assign_stats(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  defp assign_stats(socket, :init) do
    stats = Enum.map(Reports.kpi_list(), &{&1, "loading.."})

    org_id = get_org_id(socket)

    assign(socket, Keyword.merge(stats, page_title: "Glific Dashboard"))
    |> assign(get_chart_data(org_id))
  end

  defp assign_stats(socket, :call) do
    Enum.each(Reports.kpi_list(), &send(self(), {:get_stats, &1}))
    org_id = get_org_id(socket)
    assign(socket, get_chart_data(org_id))
  end

  @doc false
  @spec get_org_id(Phoenix.LiveView.Socket.t()) :: non_neg_integer()
  def get_org_id(socket) do
    socket.assigns[:current_user].organization_id
  end

  @doc false
  @spec get_chart_data(non_neg_integer()) :: list()
  def get_chart_data(org_id) do
    [
      contact_chart_data: %{
        data: fetch_date_formatted_data("contacts", org_id),
        labels: fetch_date_labels("contacts", org_id)
      },
      conversation_chart_data: %{
        data: fetch_date_formatted_data("stats", org_id),
        labels: fetch_date_labels("stats", org_id)
      },
      messages_chart_data: %{
        data: fetch_hourly_data(org_id),
        labels: Enum.to_list(0..23),
        label: ["Inbound", "Outbound"]
      },
      optin_chart_data: %{
        data: fetch_count_data(:optin_chart_data, org_id),
        labels: ["Opted In", "Opted Out", "Non Opted"]
      },
      notification_chart_data: %{
        data: fetch_count_data(:notification_chart_data, org_id),
        labels: ["Critical", "Warning", "Information"]
      },
      message_type_chart_data: %{
        data: fetch_count_data(:message_type_chart_data, org_id),
        labels: ["Inbound", "Outbound"]
      },
      broadcast_data: fetch_table_data(:broadcasts, org_id),
      broadcast_headers: ["Flow Name", "Group Name", "Started At", "Completed At"],
      contact_pie_chart_data: fetch_contact_pie_chart_data(org_id)
    ]
  end

  defp fetch_table_data(:broadcasts, org_id) do
    Reports.get_broadcast_data(org_id)
  end

  @spec fetch_count_data(atom(), non_neg_integer()) :: list()
  defp fetch_count_data(:optin_chart_data, org_id) do
    [
      Reports.get_kpi(:opted_in_contacts_count, org_id),
      Reports.get_kpi(:opted_out_contacts_count, org_id),
      Reports.get_kpi(:non_opted_contacts_count, org_id)
    ]
  end

  defp fetch_count_data(:notification_chart_data, org_id) do
    [
      Reports.get_kpi(:critical_notification_count, org_id),
      Reports.get_kpi(:warning_notification_count, org_id),
      Reports.get_kpi(:information_notification_count, org_id)
    ]
  end

  defp fetch_count_data(:message_type_chart_data, org_id) do
    [
      Reports.get_kpi(:inbound_messages_count, org_id),
      Reports.get_kpi(:outbound_messages_count, org_id)
    ]
  end

  @spec fetch_hourly_data(non_neg_integer()) :: list()
  defp fetch_hourly_data(org_id) do
    [
      Reports.get_messages_data(org_id) |> Map.values() |> Enum.into([], & &1.inbound),
      Reports.get_messages_data(org_id) |> Map.values() |> Enum.into([], & &1.outbound)
    ]
  end

  @spec fetch_date_formatted_data(String.t(), non_neg_integer()) :: list()
  defp fetch_date_formatted_data(table_name, org_id) do
    Reports.get_kpi_data(org_id, table_name)
    |> Map.values()
  end

  @spec fetch_date_labels(String.t(), non_neg_integer()) :: list()
  defp fetch_date_labels(table_name, org_id) do
    Reports.get_kpi_data(org_id, table_name)
    |> Map.keys()
  end

  @spec fetch_contact_pie_chart_data(non_neg_integer()) :: list()
  defp fetch_contact_pie_chart_data(org_id) do
    Reports.get_contact_data(org_id)
    |> Enum.reduce(%{data: [], labels: []}, fn [label, count], acc ->
      data = acc.data ++ [count]
      labels = acc.labels ++ [label]
      %{data: data, labels: labels}
    end)
  end
end
