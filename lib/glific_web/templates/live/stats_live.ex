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
             contact_pie_chart_data: contact_type_chart_data
           }
         } = socket
       ) do
    socket
    |> assign(
      contact_dataset: make_bar_chart_dataset(contact_chart_data),
      conversation_dataset: make_bar_chart_dataset(conversation_chart_data),
      optin_dataset: make_pie_chart_dataset(optin_chart_data),
      notification_dataset: make_pie_chart_dataset(notification_chart_data),
      message_dataset: make_pie_chart_dataset(message_type_chart_data),
      contact_type_dataset: make_pie_chart_dataset(contact_type_chart_data)
    )
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
             contact_type_dataset: contact_type_dataset
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
      contact_type_chart_svg: render_pie_chart("Contact Session Status", contact_type_dataset)
    )
  end

  @doc """
  Render bar chart from dataset, returns SVG
  """
  @spec render_bar_chart(String.t(), Contex.Dataset.t()) :: {:safe, [any()]}
  def render_bar_chart(title, dataset) do
    opts = barchart_opts(title)

    Contex.Plot.new(dataset, Contex.BarChart, 500, 400, opts)
    |> Contex.Plot.to_svg()
  end

  defp barchart_opts(title) do
    [
      colour_palette: ["129656", "93A29B", "EBEDEC", "B5D8C7"],
      data_labels: true,
      title: title,
      axis_label_rotation: 45
    ]
  end

  defp piechart_opts(title, category_col \\ "Type", value_col \\ "Value") do
    [
      mapping: %{category_col: category_col, value_col: value_col},
      colour_palette: ["129656", "93A29B", "EBEDEC", "B5D8C7"],
      legend_setting: :legend_bottom,
      data_labels: false,
      title: title
    ]
  end


  @doc """
  Render pie chart from dataset, returns SVG
  """
  @spec render_pie_chart(String.t(), Contex.Dataset.t()) :: {:safe, [any()]}
  def render_pie_chart(title, dataset) do
    opts = piechart_opts(title)
    plot = Contex.Plot.new(dataset, Contex.PieChart, 500, 400, opts)
    has_no_data = Enum.any?(dataset.data, fn {_label, value} -> is_nil(value) end)

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
      contact_pie_chart_data: fetch_count_data(:contact_type, org_id)
    ]
  end

  defp fetch_table_data(:broadcasts, org_id) do
    Reports.get_broadcast_data(org_id)
  end

  @spec fetch_count_data(atom(), non_neg_integer()) :: list()
  defp fetch_count_data(:optin_chart_data, org_id) do
    opted_in = Reports.get_kpi(:opted_in_contacts_count, org_id)
    opted_out = Reports.get_kpi(:opted_out_contacts_count, org_id)
    non_opted = Reports.get_kpi(:non_opted_contacts_count, org_id)

    [
      {"Opted In: #{opted_in}", opted_in},
      {"Opted Out: #{opted_out}", opted_out},
      {"Non Opted: #{non_opted}", non_opted}
    ]
  end

  defp fetch_count_data(:notification_chart_data, org_id) do
    critical = Reports.get_kpi(:critical_notification_count, org_id)
    warning = Reports.get_kpi(:warning_notification_count, org_id)
    information = Reports.get_kpi(:information_notification_count, org_id)

    [
      {"Critical: #{critical}", critical},
      {"Warning: #{warning}", warning},
      {"Information: #{information}", information}
    ]
  end

  defp fetch_count_data(:message_type_chart_data, org_id) do
    inbound = Reports.get_kpi(:inbound_messages_count, org_id)
    outbound = Reports.get_kpi(:outbound_messages_count, org_id)

    [
      {"Inbound: #{inbound}", inbound},
      {"Outbound: #{outbound}", outbound}
    ]
  end

  defp fetch_count_data(:contact_type, org_id) do
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
end
