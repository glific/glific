defmodule GlificWeb.StatsLive do
  @moduledoc """
  StatsLive uses phoenix live view to show current stats
  """
  use GlificWeb, :live_view

  alias Glific.Reports
  alias Contex.Plot

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
    |> assign_dataset()
    |> assign_chart_svg()
  end

  defp assign_stats(socket, :call) do
    Enum.each(Reports.kpi_list(), &send(self(), {:get_stats, &1}))
    org_id = get_org_id(socket)
    assign(socket, get_chart_data(org_id))
    |> assign_dataset()
    |> assign_chart_svg()
  end

  def assign_dataset(
    %{assigns: %{
      contact_chart_data: contact_chart_data,
      conversation_chart_data: conversation_chart_data,
      optin_chart_data: optin_chart_data,
      notification_chart_data: notification_chart_data}
    } = socket) do
      socket
      |> assign(
        contact_dataset:
        make_bar_chart_dataset(contact_chart_data),
        conversation_dataset:
        make_bar_chart_dataset(conversation_chart_data),
        optin_dataset:
        make_pie_chart_dataset(:optin, optin_chart_data),
        notification_dataset:
        make_pie_chart_dataset(:notification, notification_chart_data)
      )
  end

  defp make_bar_chart_dataset(data) do
    Contex.Dataset.new(data)
  end

  defp make_pie_chart_dataset(:optin, data) do #multiple of these
    Contex.Dataset.new(data, ["Type", "Value"])
  end

  defp make_pie_chart_dataset(:notification, data) do
    Contex.Dataset.new(data, ["Type", "Value"]) |> IO.inspect(label: "DATASET")
  end

  @spec assign_chart_svg(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_chart_svg(%{assigns: %{contact_dataset: contact_dataset,
                                    conversation_dataset: conversation_dataset,
                                    optin_dataset: optin_dataset,
                                    notification_dataset: notification_dataset}} = socket) do
    socket
    |> assign(contact_chart_svg: render_bar_chart(contact_dataset),
              conversation_chart_svg: render_bar_chart(conversation_dataset),
              optin_chart_svg: render_pie_chart(:optin, optin_dataset),
              notification_chart_svg: render_pie_chart(:notification, notification_dataset)
              )
  end

  defp render_bar_chart(dataset) do
    Contex.Plot.new(dataset, Contex.BarChart, 600, 400)
    |> Contex.Plot.to_svg()
  end

  defp render_pie_chart(:optin, dataset) do
    opts = [
      mapping: %{category_col: "Type", value_col: "Value"},
      colour_palette: ["fbb4ae", "b3cde3", "ccebc5"],
      legend_setting: :legend_right,
      data_labels: true,
      title: "Opted In Data"
    ]
    plot = Contex.Plot.new(dataset, Contex.PieChart, 600, 400, opts)
    [{_, v1}, {_, v2}, {_, v3}] = dataset.data |> IO.inspect(label: "DATASET.DATA")
    if [0,0,0] === [v1, v2, v3] do
      Jason.encode!("No data in the past month")
    else
      Contex.Plot.to_svg(plot)
    end
  end

  defp render_pie_chart(:notification, dataset) do
    opts = [
      mapping: %{category_col: "Type", value_col: "Value"},
      colour_palette: ["fbb4ae", "b3cde3", "ccebc5"],
      legend_setting: :legend_right,
      data_labels: true,
      title: "Notification Data"
    ]
    plot = Contex.Plot.new(dataset, Contex.PieChart, 600, 400, opts)
    [{_, v1}, {_, v2}, {_, v3}] = dataset.data |> IO.inspect(label: "DATASET.DATA")
    if [0,0,0] === [v1, v2, v3] do
      Jason.encode!("No Notifications in the past month")
    else
      Contex.Plot.to_svg(plot)
    end
  end

  @doc false
  @spec get_org_id(Phoenix.LiveView.Socket.t()) :: non_neg_integer()
  def get_org_id(socket) do
    socket.assigns[:current_user].organization_id
  end

  #GlificWeb.StatsLive.fetch_date_formatted_data("contacts", 1)
  @doc false
  @spec get_chart_data(non_neg_integer()) :: list()
  def get_chart_data(org_id) do
    [
      contact_chart_data:  Reports.get_kpi_data_new(org_id, "contacts"),
      conversation_chart_data: Reports.get_kpi_data_new(org_id, "messages_conversations"),
      optin_chart_data: fetch_count_data(:optin_chart_data, org_id),
      notification_chart_data: fetch_count_data(:notification_chart_data, org_id),
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
      {"Opted In", Reports.get_kpi(:opted_in_contacts_count, org_id)},
      {"Opted Out", Reports.get_kpi(:opted_out_contacts_count, org_id)},
      {"Non Opted", Reports.get_kpi(:non_opted_contacts_count, org_id)}
    ]
  end

  defp fetch_count_data(:notification_chart_data, org_id) do
    [
      {"Critical", Reports.get_kpi(:critical_notification_count, org_id)},
      {"Warning", Reports.get_kpi(:warning_notification_count, org_id)},
      {"Information", Reports.get_kpi(:information_notification_count, org_id)}
    ]
  end

  defp fetch_count_data(:message_type_chart_data, org_id) do
    [
      Reports.get_kpi(:inbound_messages_count, org_id),
      Reports.get_kpi(:outbound_messages_count, org_id)
    ]
  end

  @spec fetch_date_formatted_data(String.t(), non_neg_integer()) :: list()
  def fetch_date_formatted_data(table_name, org_id) do
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

  #def update(assigns, socket) do
  #  {:ok,
   # socket
   # |> assign(assigns)
   # |> assign_chart_data()
   # |> assign_dataset()
   # |> assign_chart()
    #|> assign_chart_svg()}
 # end









end
