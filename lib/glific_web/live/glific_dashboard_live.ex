defmodule GlificWeb.GlificDashboardLive do
  use GlificWeb, :live_view

  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Glific Dashboard",
        conversation_count: 40,
        active_flow_count: 50,
        contact_count: 50,
        opted_in_contacts_count: 50,
        opted_out_contacts_count: 50
      )

    {:ok, socket}
  end
end
