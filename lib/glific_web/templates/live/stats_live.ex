defmodule GlificWeb.StatsLive do
  @moduledoc """
  StatsLive uses phoenix live view to show current stats
  """
  use GlificWeb, :live_view

  alias Glific.Reports
  @colour_palette ["129656", "93A29B", "EBEDEC", "B5D8C7"]
  @hourly_timestamps [
    "12:30AM",
    "01:30AM",
    "02:30AM",
    "03:30AM",
    "04:30AM",
    "05:30AM",
    "06:30AM",
    "07:30AM",
    "08:30AM",
    "09:30AM",
    "10:30AM",
    "11:30AM",
    "12:30PM",
    "01:30PM",
    "02:30PM",
    "03:30PM",
    "04:30PM",
    "05:30PM",
    "06:30PM",
    "07:30PM",
    "08:30PM",
    "09:30PM",
    "10:30PM",
    "11:30PM"
  ]

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

  @doc false
  @spec handle_event(any(), any(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("export", %{"chart" => chart}, socket) do
    org_id = get_org_id(socket)
    data = get_export_data(String.to_atom(chart), org_id)
    csv = Enum.map_join(data, "\n", &Enum.join(&1, ","))

    {:noreply,
     socket
     |> push_event("download-file", %{
       data: csv,
       filename: chart <> ".csv"
     })}
  end

  defp get_export_data(:optin, org_id) do
    Reports.get_export_data(:optin, org_id)
    |> List.insert_at(0, ["ID", "Name", "Phone", "Optin Status"])
  end

  defp get_export_data(:contacts, org_id) do
    Reports.get_kpi_data(org_id, "contacts")
    |> Enum.map(fn {date, count} -> [date, count] end)
    |> List.insert_at(0, ["Date", "Number"])
  end

  defp get_export_data(:conversations, org_id) do
    Reports.get_kpi_data(org_id, "messages_conversations")
    |> Enum.map(fn {date, count} -> [date, count] end)
    |> List.insert_at(0, ["Date", "Number"])
  end

  defp get_export_data(:notifications, org_id) do
    Reports.get_export_data(:notifications, org_id)
    |> List.insert_at(0, ["ID", "Category", "Severity"])
  end

  defp get_export_data(:messages, org_id) do
    Reports.get_export_data(:messages, org_id)
    |> List.insert_at(0, ["ID", "Inbound", "Outbound"])
  end

  defp get_export_data(:contact_type, org_id) do
    Reports.get_export_data(:contact_type, org_id)
    |> List.insert_at(0, ["ID", "Name", "Phone", "BSP Status"])
  end

  defp get_export_data(:active_hour, org_id) do
    fetch_hourly_data(org_id)
    |> Enum.map(fn {hour, inbound, outbound} -> [hour, inbound, outbound] end)
    |> List.insert_at(0, ["Hour", "Inbound", "Outbound"])
  end

  defp get_export_data(:table, org_id) do
    fetch_table_data(:broadcasts, org_id)
    |> List.insert_at(0, ["Flow Name", "Group Name", "Started At", "Completed At"])
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

  @spec assign_dataset(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_dataset(
         %{
           assigns: %{
             contact_chart_data: contact_chart_data,
             conversation_chart_data: conversation_chart_data,
             optin_chart_data: optin_chart_data,
             notification_chart_data: notification_chart_data,
             message_type_chart_data: message_type_chart_data,
             contact_pie_chart_data: contact_type_chart_data,
             messages_chart_data: messages_chart_data
           }
         } = socket
       ) do
    socket
    |> assign(
      contact_dataset: make_bar_chart_dataset(contact_chart_data, ["Date", "Daily Contacts"]),
      conversation_dataset:
        make_bar_chart_dataset(conversation_chart_data, ["Hour", "Daily Conversations"]),
      optin_dataset: make_pie_chart_dataset(optin_chart_data),
      notification_dataset: make_pie_chart_dataset(notification_chart_data),
      message_dataset: make_pie_chart_dataset(message_type_chart_data),
      contact_type_dataset: make_pie_chart_dataset(contact_type_chart_data),
      messages_dataset: make_series_bar_chart_dataset(messages_chart_data)
    )
  end

  defp make_series_bar_chart_dataset(data) do
    Contex.Dataset.new(data, ["Hour", "Inbound", "Outbound"])
  end

  defp make_bar_chart_dataset(data, opts) do
    Contex.Dataset.new(data, opts)
  end

  @doc """
  Create Bar chart dataset from rows of data
  """
  @spec make_bar_chart_dataset([any()]) :: Contex.Dataset.t()
  def make_bar_chart_dataset(data) do
    Contex.Dataset.new(data)
  end

  @doc """
  Create Pie chart dataset from rows of data
  """
  @spec make_pie_chart_dataset([any()]) :: Contex.Dataset.t()
  def make_pie_chart_dataset(data) do
    Contex.Dataset.new(data, ["Type", "Value"])
  end

  @spec assign_chart_svg(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_chart_svg(
         %{
           assigns: %{
             contact_dataset: contact_dataset,
             conversation_dataset: conversation_dataset,
             optin_dataset: optin_dataset,
             notification_dataset: notification_dataset,
             message_dataset: message_dataset,
             contact_type_dataset: contact_type_dataset,
             messages_dataset: messages_dataset
           }
         } = socket
       ) do
    socket
    |> assign(
      contact_chart_svg: render_bar_chart("Contacts", contact_dataset),
      conversation_chart_svg: render_bar_chart("Conversations", conversation_dataset),
      optin_chart_svg: render_pie_chart("Contacts Optin Status", optin_dataset),
      notification_chart_svg: render_pie_chart("Notifications", notification_dataset),
      message_chart_svg: render_pie_chart("Messages", message_dataset),
      contact_type_chart_svg: render_pie_chart("Contact Session Status", contact_type_dataset),
      messages_chart_svg: render_bar_chart("Most Active Hour", messages_dataset)
    )
  end

  @doc """
  Render bar chart from dataset, returns SVG
  """
  @spec render_bar_chart(String.t(), Contex.Dataset.t()) :: {:safe, [any()]}
  def render_bar_chart("Most Active Hour" = title, dataset) do
    opts = series_barchart_opts(title)

    if Enum.empty?(dataset.data) do
      Jason.encode!(title <> ": No data")
    else
      Contex.Plot.new(dataset, Contex.BarChart, 1600, 400, opts)
      |> Contex.Plot.to_svg()
    end
  end

  def render_bar_chart(title, dataset) do
    opts = barchart_opts(title)

    Contex.Plot.new(dataset, Contex.BarChart, 700, 350, opts)
    |> Contex.Plot.to_svg()
  end

  @doc false
  @spec render_button_svg :: {:safe, any()}
  def render_button_svg do
    ~S"""
    <svg width="24" height="25" viewBox="0 0 24 25" fill="none" xmlns="http://www.w3.org/2000/svg">
      <mask
        id="mask0_1136_7518"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="24"
        height="25"
      >
        <rect width="24" height="24.0037" fill="#D9D9D9" />
      </mask>
      <g mask="url(#mask0_1136_7518)">
        <path
          d="M12 16.0019L7 11.0011L8.4 9.55086L11 12.1513V4H13V12.1513L15.6 9.55086L17 11.0011L12 16.0019ZM6 20.0025C5.45 20.0025 4.97917 19.8066 4.5875 19.4149C4.19583 19.0232 4 18.5523 4 18.0022V15.0017H6V18.0022H18V15.0017H20V18.0022C20 18.5523 19.8042 19.0232 19.4125 19.4149C19.0208 19.8066 18.55 20.0025 18 20.0025H6Z"
          fill="#CCCCCC"
        />
      </g>
    </svg>
    """
    |> raw()
  end

  defp barchart_opts(_title) do
    [
      colour_palette: @colour_palette,
      data_labels: false,
      title: false,
      axis_label_rotation: 45,
      legend_setting: :legend_bottom
    ]
  end

  defp series_barchart_opts(_title) do
    [
      colour_palette: @colour_palette,
      mapping: %{category_col: "Hour", value_cols: ["Inbound", "Outbound"]},
      data_labels: false,
      title: false,
      axis_label_rotation: 45,
      type: :grouped,
      padding: 20,
      legend_setting: :legend_bottom
    ]
  end

  defp piechart_opts(_title, category_col \\ "Type", value_col \\ "Value") do
    [
      mapping: %{category_col: category_col, value_col: value_col},
      colour_palette: @colour_palette,
      legend_setting: :legend_right,
      data_labels: false,
      title: false
    ]
  end

  @doc """
  Render pie chart from dataset, returns SVG
  """
  @spec render_pie_chart(String.t(), Contex.Dataset.t()) :: {:safe, [any()]}
  def render_pie_chart(title, dataset) do
    opts = piechart_opts(title)
    plot = Contex.Plot.new(dataset, Contex.PieChart, 700, 400, opts)

    has_no_data =
      Enum.any?(dataset.data, fn {_label, value} -> is_nil(value) end) or
        Enum.all?(dataset.data, fn {_label, value} -> value == 0 end)

    if has_no_data do
      Jason.encode!(title <> ": No data")
    else
      Contex.Plot.to_svg(plot)
    end
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
      contact_chart_data: Reports.get_kpi_data(org_id, "contacts"),
      conversation_chart_data: Reports.get_kpi_data(org_id, "messages_conversations"),
      optin_chart_data: fetch_count_data(:optin_chart_data, org_id),
      notification_chart_data: fetch_count_data(:notification_chart_data, org_id),
      message_type_chart_data: fetch_count_data(:message_type_chart_data, org_id),
      broadcast_data: fetch_table_data(:broadcasts, org_id),
      broadcast_headers: ["Flow Name", "Group Name", "Started At", "Completed At"],
      contact_pie_chart_data: fetch_count_data(:contact_type, org_id),
      messages_chart_data: fetch_hourly_data(org_id)
    ]
  end

  defp fetch_table_data(:broadcasts, org_id) do
    Reports.get_broadcast_data(org_id)
  end

  @doc """
  Fetch optin chart count data
  """
  @spec fetch_count_data(atom(), non_neg_integer()) :: list()
  def fetch_count_data(:optin_chart_data, org_id) do
    opted_in = Reports.get_kpi(:opted_in_contacts_count, org_id)
    opted_out = Reports.get_kpi(:opted_out_contacts_count, org_id)
    non_opted = Reports.get_kpi(:non_opted_contacts_count, org_id)

    [
      {"Opted In: #{opted_in}", opted_in},
      {"Opted Out: #{opted_out}", opted_out},
      {"Non Opted: #{non_opted}", non_opted}
    ]
  end

  def fetch_count_data(:notification_chart_data, org_id) do
    critical = Reports.get_kpi(:critical_notification_count, org_id)
    warning = Reports.get_kpi(:warning_notification_count, org_id)
    information = Reports.get_kpi(:information_notification_count, org_id)

    [
      {"Critical: #{critical}", critical},
      {"Warning: #{warning}", warning},
      {"Information: #{information}", information}
    ]
  end

  def fetch_count_data(:message_type_chart_data, org_id) do
    inbound = Reports.get_kpi(:inbound_messages_count, org_id)
    outbound = Reports.get_kpi(:outbound_messages_count, org_id)

    [
      {"Inbound: #{inbound}", inbound},
      {"Outbound: #{outbound}", outbound}
    ]
  end

  def fetch_count_data(:contact_type, org_id) do
    Reports.get_contact_data(org_id)
    |> Enum.reduce([], fn [status, count], acc ->
      contact_status =
        case status do
          :none -> "None"
          :session_and_hsm -> "Session and HSM"
          :hsm -> "HSM"
          :session -> "Session"
        end

      acc ++ [{"#{contact_status}: #{count}", count}]
    end)
  end

  @doc false
  @spec fetch_hourly_data(non_neg_integer()) :: list()
  def fetch_hourly_data(org_id) do
    hourly_data = Reports.get_messages_data(org_id)

    Enum.reduce(@hourly_timestamps, [], fn time, acc ->
      message_map = Map.get(hourly_data, time)
      acc ++ [{time, message_map.inbound, message_map.outbound}]
    end)
  end
end
