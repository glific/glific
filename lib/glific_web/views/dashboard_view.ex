defmodule GlificWeb.DashboardView do
  use GlificWeb, :view

  def render_dashboard(template_name, assigns) do
    Phoenix.View.render_to_string(GlificWeb.DashboardView, template_name, assigns)
  end
end
