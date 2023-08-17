defmodule GlificWeb.DashboardView do
  use GlificWeb, :view

  def render_dashboard(template_name, assigns) do
    template = Phoenix.View.render_to_string(GlificWeb.DashboardView, template_name, assigns)
    template
  end
end
